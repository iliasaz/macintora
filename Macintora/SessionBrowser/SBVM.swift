import Foundation
import AppKit
import OracleNIO
import NIOCore
import NIOPosix
import Logging
import os

@MainActor
@Observable
final class SBVM {
    var mainConnection: MainConnection
    var connStatus: ConnectionStatus = .disconnected
    var isExecuting = false
    var activeOnly: Bool = true {
        didSet { populateData() }
    }
    var userOnly: Bool = true {
        didSet { populateData() }
    }
    var localInstanceOnly: Bool = true {
        didSet { populateData() }
    }

    private var conn: OracleConnection?
    var autoColWidth = true
    var rows: [DisplayRow] = []
    var columnLabels: [String] = []
    var dataHasChanged = false
    let mainSql = "select * from gv$session where 1=1 $WHERE$ order by decode(sid, $SID$, 1, 0) desc, decode(sql_trace,'ENABLED',1,0) desc, decode(status,'ACTIVE',0,'KILLED',1,'INACTIVE',2,3), decode(wait_class, 'Idle', 0, 1) desc, seconds_in_wait desc"

    var oraSession: OracleSession?
    var sqlMonOperations: [String: Int] = [:]

    private let oracleLogger: Logging.Logger = {
        var logger = Logging.Logger(label: "com.iliasazonov.macintora.oracle.sb")
        logger.logLevel = .notice
        return logger
    }()

    init(mainConnection: MainConnection) {
        self.mainConnection = mainConnection
    }

    static func preview() -> SBVM {
        SBVM(mainConnection: MainConnection.preview())
    }

    func sort(by colName: String?, ascending: Bool) {
        guard let colName, let colIndex = columnLabels.firstIndex(of: colName), colIndex > 0 else { return }
        let dataIndex = colIndex - 1
        if ascending {
            rows.sort { DisplayRow.less(colIndex: dataIndex, lhs: $0, rhs: $1) }
        } else {
            rows.sort { DisplayRow.less(colIndex: dataIndex, lhs: $1, rhs: $0) }
        }
    }

    func buildSessionListSql() -> String {
        var whereConditions = ""
        if activeOnly {
            whereConditions.append(" and (status = 'ACTIVE' or (sid = \(mainConnection.mainSession?.sid ?? -1) and serial# = \(mainConnection.mainSession?.serial ?? -1)))")
        }
        if userOnly {
            whereConditions.append(" and (type = 'USER')")
        }
        if localInstanceOnly && mainConnection.mainSession?.instance != nil {
            whereConditions.append(" and (inst_id = \(mainConnection.mainSession?.instance ?? -1))")
        }
        return mainSql
            .replacing("$SID$", with: String(mainConnection.mainSession?.sid ?? -1))
            .replacing("$WHERE$", with: whereConditions)
    }

    func connectAndQuery() {
        connStatus = .changing
        let details = mainConnection.mainConnDetails
        let aliases = loadTnsAliases()
        let logger = oracleLogger
        Task { [weak self] in
            await self?.performConnect(details: details, aliases: aliases, logger: logger)
        }
    }

    private func performConnect(details: ConnectionDetails, aliases: [TnsEntry], logger: Logging.Logger) async {
        let configuration: OracleConnection.Configuration
        do {
            configuration = try OracleEndpoint.configuration(for: details, aliases: aliases)
        } catch {
            log.error("SB connection config failed: \(error.localizedDescription, privacy: .public)")
            connStatus = .disconnected
            return
        }
        do {
            let newConn = try await OracleConnection.connect(
                on: OracleEventLoopGroup.shared.next(),
                configuration: configuration,
                id: Int.random(in: 1...Int.max),
                logger: logger
            )
            // Drain so oracle-nio's `didTerminate` cleanup doesn't race the
            // next execute. See `MainDocumentVM.performConnect`.
            if let alterStream = try? await newConn.execute(
                "ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD HH24:MI:SS'",
                logger: logger
            ) {
                for try await _ in alterStream { }
            }
            self.conn = newConn
            self.oraSession = await MainDocumentVM.fetchOracleSession(on: newConn, logger: logger)
            connStatus = .connected
            self.rows.removeAll()
            self.isExecuting = true
            await self.refreshSessions()
        } catch {
            log.error("SB connection error: \(error.localizedDescription, privacy: .public)")
            connStatus = .disconnected
        }
    }

    func disconnect() {
        connStatus = .changing
        let capturedConn = conn
        conn = nil
        Task { [weak self] in
            try? await capturedConn?.close()
            self?.oraSession = nil
            self?.connStatus = .disconnected
        }
    }

    private nonisolated func loadTnsAliases() -> [TnsEntry] {
        let defaultPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.oracle/tnsnames.ora"
        let path = UserDefaults.standard.string(forKey: "tnsnamesPath") ?? defaultPath
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return TnsParser.parse(contents)
    }

    func populateData() {
        guard connStatus == .connected else { return }
        self.rows.removeAll()
        self.isExecuting = true
        Task { [weak self] in
            await self?.refreshSessions()
        }
    }

    private func refreshSessions() async {
        guard let conn else {
            isExecuting = false
            return
        }
        let sql = buildSessionListSql()
        let logger = oracleLogger
        do {
            var options = StatementOptions()
            options.prefetchRows = 1000
            let stream = try await conn.execute(OracleStatement(stringLiteral: sql), options: options, logger: logger)
            var labels = DisplayRowBuilder.columnLabels(for: stream.columns)
            var collected: [DisplayRow] = []
            var idx = 0
            for try await row in stream {
                collected.append(DisplayRowBuilder.make(from: row, id: idx, columnLabels: labels))
                idx += 1
                if idx >= 10_000 { break }
            }
            labels.insert("#", at: 0)
            self.columnLabels = labels
            self.rows = collected
            self.dataHasChanged = true
        } catch {
            log.error("Session query failed: \(error.localizedDescription, privacy: .public)")
        }
        self.isExecuting = false
    }

    func startTrace(sid: Int, serial: Int) {
        isExecuting = true
        let logger = oracleLogger
        let stmt: OracleStatement = """
            begin DBMS_MONITOR.SESSION_TRACE_ENABLE(session_id => \(sid), serial_num => \(serial), waits => true, binds => true); end;
            """
        Task { [weak self] in
            if let stream = try? await self?.conn?.execute(stmt, logger: logger) {
                for try await _ in stream { }
            }
            self?.populateData()
        }
    }

    func stopTrace(sid: Int, serial: Int) {
        isExecuting = true
        let logger = oracleLogger
        let stmt: OracleStatement = """
            begin DBMS_MONITOR.SESSION_TRACE_DISABLE(session_id => \(sid), serial_num => \(serial)); end;
            """
        Task { [weak self] in
            if let stream = try? await self?.conn?.execute(stmt, logger: logger) {
                for try await _ in stream { }
            }
            self?.populateData()
        }
    }

    func copyTraceFileName(paddr: String, instNum: Int) {
        isExecuting = true
        let logger = oracleLogger
        let stmt: OracleStatement = """
            select tracefile from gv$process where addr = \(paddr) and inst_id = \(instNum)
            """
        Task { [weak self] in
            guard let self, let conn = self.conn else { return }
            var traceFileName: String? = nil
            do {
                let stream = try await conn.execute(stmt, logger: logger)
                for try await row in stream {
                    traceFileName = row.makeRandomAccess().optString("TRACEFILE")
                    break
                }
            } catch {
                log.error("copyTraceFileName failed: \(error.localizedDescription, privacy: .public)")
            }
            self.isExecuting = false
            guard let traceFileName else { return }
            let pasteBoard = NSPasteboard.general
            pasteBoard.clearContents()
            pasteBoard.setString(traceFileName, forType: .string)
        }
    }

    func startSqlMonitor(sid: Int, serial: Int) {
        isExecuting = true
        let logger = oracleLogger
        let name = "SESS_\(sid),\(serial)"
        let eidRef = OracleRef(dataType: .number)
        let stmt: OracleStatement = """
            begin \(eidRef) := DBMS_SQL_MONITOR.BEGIN_OPERATION(dbop_name => \(name), forced_tracking => 'Y', session_id => \(sid), session_serial => \(serial)); end;
            """
        Task { [weak self] in
            guard let self, let conn = self.conn else { return }
            do {
                try await conn.execute(stmt, logger: logger)
                let eid = try eidRef.decode(as: Int.self)
                self.sqlMonOperations[name] = eid
            } catch {
                log.error("DBMS_SQL_MONITOR.BEGIN_OPERATION failed: \(error.localizedDescription, privacy: .public)")
            }
            self.isExecuting = false
        }
    }

    func stopSqlMonitor(sid: Int, serial: Int) {
        isExecuting = true
        let logger = oracleLogger
        let name = "SESS_\(sid),\(serial)"
        guard let dopEid = sqlMonOperations[name] else {
            log.error("no active DBMS_SQL_MON operation for session \(name)")
            isExecuting = false
            return
        }
        let stmt: OracleStatement = """
            begin DBMS_SQL_MONITOR.END_OPERATION(dbop_name => \(name), dop_eid => \(dopEid)); end;
            """
        Task { [weak self] in
            if let stream = try? await self?.conn?.execute(stmt, logger: logger) {
                for try await _ in stream { }
            }
            self?.populateData()
        }
    }

    func killSession(sid: Int, serial: Int) {
        isExecuting = true
        let logger = oracleLogger
        let sql = "alter system kill session '\(sid),\(serial)' immediate"
        Task { [weak self] in
            if let stream = try? await self?.conn?.execute(OracleStatement(stringLiteral: sql), logger: logger) {
                for try await _ in stream { }
            }
            self?.populateData()
        }
    }
}
