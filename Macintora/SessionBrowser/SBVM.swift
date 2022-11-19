//
//  SBVM.swift
//  Macintora
//
//  Created by Ilia Sazonov on 9/16/22.
//

import Foundation
import SwiftOracle

struct OracleSession: CustomStringConvertible {
    var description: String { "sid: \(sid), serial#: \(serial), instance: \(instance), timezone: \(dbTimeZone.debugDescription)" }
    
    let sid: Int
    let serial: Int
    let instance: Int
    let dbTimeZone: TimeZone?
    
    static func preview() -> OracleSession {
        OracleSession(sid: 100, serial: 2000, instance: 2, dbTimeZone: .current)
    }
}

struct SBConnDetails {
    let mainConnDetails: ConnectionDetails
    let mainSession: OracleSession?
    
    static func preview() -> SBConnDetails {
        SBConnDetails(mainConnDetails: ConnectionDetails.preview(), mainSession: OracleSession.preview())
    }
}

class SBVM: ObservableObject {
    var connDetails: SBConnDetails
    @Published var connStatus: ConnectionStatus = .disconnected
    @Published var isExecuting = false
    private var conn: Connection?
    var autoColWidth = true
    var rows = [SwiftyRow]()
    var columnLabels = [String]()
    var dataHasChanged = false
    let mainSql = "select * from v$session order by decode(sid, $SID$, 1, 0) desc, decode(sql_trace,'ENABLED',1,0) desc, decode(status,'ACTIVE',0,'KILLED',1,'INACTIVE',2,3), decode(wait_class, 'Idle', 0, 1) desc, seconds_in_wait desc"
    
    var oraSession: OracleSession?
    var mainOrasession: OracleSession? { connDetails.mainSession }
    var sessionListSql: String { mainSql.replacingOccurrences(of: "$SID$", with: String(mainOrasession?.sid ?? -1)) }
    var sqlMonOperations = [String: Int]() // a dict of current DBMS_SQL_MONITOR operations in the format of [SESS_<sid><serial> : <dop_eid>]
    
    init(connDetails: SBConnDetails) {
        self.connDetails = connDetails
    }
    
    static func preview() -> SBVM {
        SBVM(connDetails: SBConnDetails.preview())
    }
    
    func sort(by colName: String?, ascending: Bool) {
        guard let colName = colName else { return }
        guard let colIndex = columnLabels.firstIndex(of: colName) else { return }
        if ascending {
            rows.sort(by: {SwiftyRow.less(colIndex: colIndex-1, lhs: $0, rhs: $1)} ) // account for row number!
        } else {
            rows.sort(by: {SwiftyRow.less(colIndex: colIndex-1, lhs: $1, rhs: $0)} )
        }
    }
    
    func connectAndQuery() {
        connStatus = .changing
        Task.detached(priority: .background) { [self] in
            let oracleService = OracleService(from_string: connDetails.mainConnDetails.tns)
            conn = Connection(service: oracleService, user: connDetails.mainConnDetails.username, pwd: connDetails.mainConnDetails.password, sysDBA: connDetails.mainConnDetails.connectionRole == .sysDBA)
            guard let conn else {
                log.error("connection object is nil")
                await MainActor.run { connStatus = .disconnected }
                return
            }
            do {
                log.debug("SB attempting to connect to \(self.connDetails.mainConnDetails.tns, privacy: .public)")
                try conn.open()
                log.debug("SB connected")
                do { try conn.setFormat(fmtType: .date, fmtString: "YYYY-MM-DD HH24:MI:SS") }
                catch {
                    log.debug("setFormat failed: \(error.localizedDescription, privacy: .public)")
                    await MainActor.run { connStatus = .disconnected }
                    return
                }
                oraSession = MainDocumentVM.getOracleSession(for: conn)
            } catch {
                log.error("SB connection error: \(error.localizedDescription, privacy: .public)")
                await MainActor.run { connStatus = .disconnected }
                return
            }
            await MainActor.run {
                connStatus = .connected
                objectWillChange.send()
                rows.removeAll()
                isExecuting = true
            }
            log.debug("populating session browser with sql: \(self.sessionListSql, privacy: .public)")
            let result = await queryData(for: sessionListSql, using: conn, maxRows: 1000, showDbmsOutput: false, prefetchSize: 1000)
            await MainActor.run {
                updateViews(with: result)
            }
        }
    }
    
    func disconnect() {
        connStatus = .changing
        Task.detached(priority: .background) { [self] in
            guard let conn = conn else {
                log.error("SB connection doesn't exist")
                await MainActor.run { connStatus = .disconnected }
                return
            }
            conn.close()
            oraSession = nil
            await MainActor.run {
                if !conn.connected {
                    connStatus = .disconnected
                    log.debug("SB disconnected")
                }
            }
        }
    }
    
    func queryData(for sql:String, using conn:Connection, maxRows: Int, showDbmsOutput: Bool = false, binds: [String: BindVar] = [:], prefetchSize: Int = 200) async -> Result<([String], [SwiftyRow], String, String), Error> {
        let result: Result<([String], [SwiftyRow], String, String), Error>
        var rows = [SwiftyRow]()
        var columnLabels = [String]()
        do {
            let cursor = try conn.cursor()
            try cursor.execute(sql, params: binds, prefetchSize: prefetchSize, enableDbmsOutput: showDbmsOutput)
            let sqlId = cursor.sqlId
            let dbmsOuput = cursor.dbmsOutputContent
            columnLabels = cursor.getColumnLabels()
            rows = [SwiftyRow]()
            var rowCnt = 0
            while let row = cursor.nextSwifty(withStringRepresentation: true), rowCnt < (maxRows == -1 ? 10000 : maxRows) {
                rows.append(row)
                rowCnt += 1
            }
            columnLabels.insert("#", at: 0)
            result = .success((columnLabels, rows, sqlId, dbmsOuput))
            log.debug("data loaded, rows.count: \(rows.count)")
        } catch DatabaseErrors.SQLError (let error) {
            log.error("\(error.description, privacy: .public)")
            result = .failure(error)
        } catch {
            log.error("\(error.localizedDescription, privacy: .public)")
            result = .failure(error)
        }
        return result
    }
    
    func executeCommand(sql: String, using conn: Connection, binds: [String: BindVar] = [:]) async -> Result<String, Error> {
        let result: Result<String, Error>
        do {
            let cursor = try conn.cursor()
            try cursor.execute(sql, params: binds, enableDbmsOutput: false)
            result = .success("")
            log.debug("command executed")
        } catch DatabaseErrors.SQLError (let error) {
            log.error("\(error.description, privacy: .public)")
            result = .failure(error)
        } catch {
            log.error("\(error.localizedDescription, privacy: .public)")
            result = .failure(error)
        }
        return result
    }
    
    func populateData() {
        objectWillChange.send()
        rows.removeAll()
        isExecuting = true
        log.debug("populating session browser with sql: \(self.sessionListSql, privacy: .public)")
        Task.detached(priority: .background) { [self] in
            let result = await queryData(for: sessionListSql, using: conn!, maxRows: 10000, showDbmsOutput: false, prefetchSize: 1000)
            await MainActor.run {
                updateViews(with: result)
            }
        }
    }
    
    func updateViews(with result: Result<([String], [SwiftyRow], String, String), Error>) {
        objectWillChange.send()
        switch result {
            case .success(let (resultColumns, resultRows, _, _)):
                self.columnLabels = resultColumns
                self.rows = resultRows
                dataHasChanged = true
            case .failure(let error):
                log.debug("Session query failed with \(error.localizedDescription, privacy: .public)")
        }
        isExecuting = false
        log.debug("end of refreshData")
    }
    
    func startTrace(sid: Int, serial: Int) {
        isExecuting = true
        let sql = "begin DBMS_MONITOR.SESSION_TRACE_ENABLE(session_id => :sid, serial_num => :serial, waits => true, binds => true); end;"
        Task.detached(priority: .background) {
            let _ = await self.executeCommand(sql: sql, using: self.conn!, binds: [":sid": BindVar(sid), ":serial": BindVar(serial)])
            await MainActor.run {
                self.populateData()
            }
        }
    }
    
    func stopTrace(sid: Int, serial: Int) {
        isExecuting = true
        let sql = "begin DBMS_MONITOR.SESSION_TRACE_DISABLE(session_id => :sid, serial_num => :serial); end;"
        Task.detached(priority: .background) {
            let _ = await self.executeCommand(sql: sql, using: self.conn!, binds: [":sid": BindVar(sid), ":serial": BindVar(serial)])
            await MainActor.run {
                self.populateData()
            }
        }
    }
    
    func startSqlMonitor(sid: Int, serial: Int) {
        isExecuting = true
        // we need the execution ID assigned by DBMS_SQL_MONITOR package so that we can stop monitoring
        let sql = "declare eid number := 0; c sys_refcursor; begin eid := DBMS_SQL_MONITOR.BEGIN_OPERATION(dbop_name => :name, forced_tracking => 'Y', session_id => :sid, session_serial => :serial); open c for select eid as value from dual; dbms_sql.return_result(c); end;"
        let name = "SESS_\(sid),\(serial)"
        let binds = [":name": BindVar(name), ":sid": BindVar(sid), ":serial": BindVar(serial)]
        Task.detached(priority: .background) {[self] in
            log.debug("Attempting to execute DBMS_SQL_MONITOR.BEGIN_OPERATION")
            let result = await queryData(for: sql, using: conn!, maxRows: 10, showDbmsOutput: false, binds: binds, prefetchSize: 10)
            switch result {
                case .success(let (_, resultRows, _, _)):
                    guard let opId = resultRows[0]["VALUE"]!.int else { log.error("DBMS_SQL_MONITOR did not return dbop_eid"); return }
                    // saving operation execution ID
                    sqlMonOperations[name] = opId
                    log.debug("Added DBMS_SQL_MONITOR composite operation for \(name) with eid = \(opId)")
                case .failure(let error):
                    log.error("DBMS_SQL_MONITOR.BEGIN_OPERATION failed with \(error.localizedDescription, privacy: .public)")
            }
            await MainActor.run {
                isExecuting = false
            }
        }
    }
    
    func stopSqlMonitor(sid: Int, serial: Int) {
        isExecuting = true
        let sql = "begin DBMS_SQL_MONITOR.END_OPERATION(dbop_name => :name, dop_eid => :dop_eid); end;"
        let name = "SESS_\(sid),\(serial)"
        guard let dopEid = sqlMonOperations[name] else { log.error("no active DBMS_SQL_MON operation for session \(name)"); return }
        Task.detached(priority: .background) {
            let _ = await self.executeCommand(sql: sql, using: self.conn!, binds: [":name": BindVar(name), ":dop_eid": BindVar(dopEid)])
            await MainActor.run {
                self.populateData()
            }
        }
    }
    
    func killSession(sid: Int, serial: Int) {
        isExecuting = true
        let sql = "alter system kill session '\(sid),\(serial)' immediate"
        Task.detached(priority: .background) {
            let _ = await self.executeCommand(sql: sql, using: self.conn!)
            await MainActor.run {
                self.populateData()
            }
        }
    }
}

