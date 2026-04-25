import Foundation
import Combine
import OracleNIO
import SwiftUI
import Logging
import os

// Mark the ObservableObject conformance as preconcurrency: ResultViewModel is
// @MainActor-isolated but SwiftUI needs to access `objectWillChange` from any
// isolation domain. Same pattern used for every other @MainActor view model.

extension os.Logger {
    // Diagnostic category for tracing SQL execution flow. Delete once the
    // all_objects hang is root-caused.
    var sqlexec: os.Logger { os.Logger(subsystem: os.Logger.subsystem, category: "sqlexec") }
}

enum RunningLogEntryType: Sendable {
    case info, error
}

struct RunningLogEntry: Sendable {
    let text: String
    let type: RunningLogEntryType
    let timestamp = Date()
}

/// State captured across `fetchMoreData` / `refreshData` calls.
///
/// Safety invariant for `@unchecked Sendable`:
/// - `OracleRowSequence.AsyncIterator` is not `Sendable`. It has value-type
///   surface but reference-typed backing (shared with the underlying stream).
/// - `ResultViewModel` guarantees a *single consumer* for any given
///   `ActiveQuery`: every entry point (`populateData`, `fetchMoreData`,
///   `refreshData`) cancels the prior `currentTask` before starting a new one,
///   so `iterator.next()` is never called concurrently on the same instance.
/// - Instances are only passed from the MainActor-bound view model into a
///   single child task, and never shared further.
///
/// Follow-up: drop `@unchecked` once oracle-nio exposes a `Sendable` row
/// sequence / iterator, or once we wrap the sequence in an actor.
private final class ActiveQuery: @unchecked Sendable {
    let sql: String
    let columnLabels: [String]
    let binds: [String: BindValue]
    let prefetch: Int
    let dbmsOutputEnabled: Bool
    var nextRowID: Int
    var iterator: OracleRowSequence.AsyncIterator

    init(
        sql: String,
        columnLabels: [String],
        binds: [String: BindValue],
        prefetch: Int,
        dbmsOutputEnabled: Bool,
        nextRowID: Int,
        iterator: OracleRowSequence.AsyncIterator
    ) {
        self.sql = sql
        self.columnLabels = columnLabels
        self.binds = binds
        self.prefetch = prefetch
        self.dbmsOutputEnabled = dbmsOutputEnabled
        self.nextRowID = nextRowID
        self.iterator = iterator
    }
}

@MainActor
public final class ResultViewModel: nonisolated ObservableObject {
    @AppStorage("rowFetchLimit") var rowFetchLimit: Int = 200
    @AppStorage("queryPrefetchSize") private var queryPrefetchSize: Int = 200

    var rows: [DisplayRow] = []
    var columnLabels: [String] = []
    var isFailed = false

    @Published var autoColWidth = true {
        willSet {
            objectWillChange.send()
            dataHasChanged = true
        }
    }

    @Published var showingLog = false
    @Published var showingBindVarInputView = false
    @Published var sqlCount: Int = 0

    var bindVarVM = BindVarInputVM()
    private(set) var resultsController: ResultsController
    var dataHasChanged = false

    var enabledDbmsOutput = true
    var runningLog: [RunningLogEntry] = []
    var runningLogStr: NSAttributedString {
        get {
            runningLog.reversed().map { element -> NSAttributedString in
                if element.type == .error {
                    return NSAttributedString(
                        string: "--------------------\n" + element.timestamp.ISO8601Format() + "\n" + element.text,
                        attributes: [.foregroundColor: NSColor.red]
                    )
                } else {
                    return NSAttributedString(
                        string: "--------------------\n" + element.timestamp.ISO8601Format() + "\n" + element.text,
                        attributes: [.foregroundColor: NSColor.textColor, .font: NSFont.monospacedSystemFont(ofSize: 12.0, weight: .regular)]
                    )
                }
            }.joined(with: "\n")
        }
        set { _ = newValue }
    }

    var currentSql: String = ""
    var sqlId: String = ""

    private var activeQuery: ActiveQuery?
    private var currentTask: Task<Void, Never>?

    /// Test-only read-only probe. True when a row stream iterator is still held
    /// from the most recent query (i.e. the connection is NOT idle). Used to
    /// verify Bug B: cancel / new-query / disconnect all must leave this `false`
    /// so the server-side cursor is closed and the connection is free.
    var hasActiveQuery: Bool { activeQuery != nil }
    private let oracleLogger: Logging.Logger = {
        var logger = Logging.Logger(label: "com.iliasazonov.macintora.oracle.results")
        logger.logLevel = .notice
        return logger
    }()

    init(parent: ResultsController) {
        resultsController = parent
    }

    // MARK: - Preview helpers

    func init_preview(_ numRows: Int, _ numCols: Int) {
        columnLabels = (0..<numCols).map { "Column \($0)" }
        rows = (0..<numRows).map { rowNum in
            DisplayRow(id: rowNum, fields: columnLabels.enumerated().map { colNum, label in
                DisplayField(
                    name: label,
                    valueString: "super very long long long long long long Value \(rowNum) - \(colNum)",
                    sortKey: .text("\(rowNum)-\(colNum)")
                )
            })
        }
    }

    // MARK: - Public intents

    func promptForBindsAndExecute(for runnableSQL: RunnableSQL, using conn: OracleConnection) {
        currentSql = runnableSQL.sql
        if runnableSQL.bindNames.isEmpty {
            if showingBindVarInputView { showingBindVarInputView = false }
            populateData(using: conn)
        } else {
            bindVarVM = BindVarInputVM(from: bindVarVM, bindNames: runnableSQL.bindNames)
            if !showingBindVarInputView { showingBindVarInputView = true }
        }
    }

    func runCurrentSQL(using conn: OracleConnection) {
        populateData(using: conn)
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        // Bug B: drop the iterator reference so oracle-nio's
        // `NIOAsyncSequenceProducerDelegate.didTerminate` fires and the
        // server-side cursor is closed — otherwise the connection stays busy
        // and the next `conn.execute(…)` deadlocks.
        activeQuery = nil
    }

    func getBinds() -> [String: BindValue] {
        bindVarVM.bindVars.reduce(into: [:]) { partial, entry in
            switch entry.type {
            case .text: partial[entry.name] = .text(entry.textValue)
            case .null: partial[entry.name] = .null
            case .date:
                if let d = entry.dateValue { partial[entry.name] = .date(d) } else { partial[entry.name] = .null }
            case .int:
                if let i = entry.intValue { partial[entry.name] = .int(i) } else { partial[entry.name] = .null }
            case .decimal:
                if let d = entry.decValue { partial[entry.name] = .decimal(d) } else { partial[entry.name] = .null }
            }
        }
    }

    func populateData(using conn: OracleConnection) {
        objectWillChange.send()
        rows.removeAll()
        sqlCount = 0
        resultsController.isExecuting = true
        // Bug B: release any iterator held from a previous cap-hit run BEFORE
        // issuing a new `conn.execute(…)` — otherwise the new execute queues
        // behind the open cursor and deadlocks.
        activeQuery = nil
        let sql = currentSql
        let binds = getBinds()
        let limit = rowFetchLimit
        // Bug A root cause: with prefetchRows > rowFetchLimit, oracle-nio
        // requests more rows than we'll consume. The server sends them — plus
        // the statement-completion signal and `readyForStatement` packet —
        // and they sit in the client's incoming buffer while we stop pulling
        // at `limit`. When the next `conn.execute(…)` is issued, oracle-nio's
        // state machine processes those buffered packets and crashes with
        // `readyForStatement received when statement is still being executed`
        // because the inner statement state hasn't transitioned through
        // .commandComplete yet. Capping `prefetchRows` to `limit` means the
        // server only sends what we'll actually consume; the cursor stays
        // cleanly mid-fetch and `fetchMoreData` can ask for more on demand.
        let prefetch = limit > 0 ? min(queryPrefetchSize, limit) : queryPrefetchSize
        let dbmsOutputEnabled = enabledDbmsOutput
        let logger = oracleLogger
        currentTask?.cancel()
        currentTask = Task { [weak self] in
            guard let self else { return }
            await self.runQueryAndLoad(
                conn: conn,
                sql: sql,
                binds: binds,
                prefetch: prefetch,
                limit: limit,
                dbmsOutputEnabled: dbmsOutputEnabled,
                logger: logger
            )
        }
    }

    private func runQueryAndLoad(
        conn: OracleConnection,
        sql: String,
        binds: [String: BindValue],
        prefetch: Int,
        limit: Int,
        dbmsOutputEnabled: Bool,
        logger: Logging.Logger
    ) async {
        let start = Date.now
        let diag = log.sqlexec
        do {
            if dbmsOutputEnabled {
                diag.notice("enter DBMSOutput.enable")
                try? await DBMSOutput.enable(on: conn, logger: logger)
                diag.notice("DBMSOutput.enable returned")
            }
            let statement = BindValue.makeStatement(sql: sql, binds: binds)
            diag.notice("enter conn.execute; prefetch=\(prefetch, privacy: .public) sql=\(sql, privacy: .public)")
            let rowStream = try await conn.execute(
                statement,
                options: OracleOptions.with(prefetchRows: prefetch),
                logger: logger
            )
            let columns = DisplayRowBuilder.columnLabels(for: rowStream.columns)
            diag.notice("conn.execute returned; columns=\(columns.count, privacy: .public)")
            var labels = columns
            labels.insert("#", at: 0)
            var iterator = rowStream.makeAsyncIterator()
            var collected: [DisplayRow] = []
            let cap = limit == -1 ? 10_000 : limit
            var idx = 0
            var exhausted = false
            while idx < cap {
                let shouldLog = idx < 3 || idx % 50 == 0
                if shouldLog { diag.notice("awaiting iterator.next() at idx=\(idx, privacy: .public)") }
                guard let row = try await iterator.next() else {
                    diag.notice("iterator exhausted at idx=\(idx, privacy: .public)")
                    exhausted = true
                    break
                }
                if shouldLog { diag.notice("iterator.next() returned at idx=\(idx, privacy: .public)") }
                if Task.isCancelled {
                    diag.notice("Task cancelled at idx=\(idx, privacy: .public)")
                    break
                }
                collected.append(DisplayRowBuilder.make(from: row, id: idx, columnLabels: columns))
                idx += 1
            }
            diag.notice("loop exited at idx=\(idx, privacy: .public) cap=\(cap, privacy: .public) exhausted=\(exhausted, privacy: .public)")

            // Bug A guard: oracle-nio serializes operations per connection. When
            // the stream is still mid-scan (cap hit before exhaustion), any
            // follow-up `conn.execute(…)` (DBMS_OUTPUT drain or v$session
            // sqlID lookup) deadlocks against the open cursor. Only issue those
            // follow-up calls when the stream ended naturally. The iterator is
            // saved to `activeQuery` below; once it's released (new query /
            // cancel / disconnect), oracle-nio's `didTerminate` closes the
            // server-side cursor and DBMS_OUTPUT buffer carries forward.
            let dbmsOutput: String
            let sqlID: String
            if exhausted {
                if dbmsOutputEnabled {
                    diag.notice("enter DBMSOutput.drain")
                    dbmsOutput = (try? await DBMSOutput.drain(on: conn, logger: logger)) ?? ""
                    diag.notice("DBMSOutput.drain returned; bytes=\(dbmsOutput.utf8.count, privacy: .public)")
                } else {
                    dbmsOutput = ""
                }
                diag.notice("fetching sqlID")
                sqlID = await Self.fetchSqlID(on: conn, logger: logger)
                diag.notice("fetched sqlID=\(sqlID, privacy: .public); applying success")
            } else {
                diag.notice("cap hit, stream still open — skipping drain/sqlID to avoid deadlock")
                dbmsOutput = ""
                sqlID = ""
            }
            self.activeQuery = ActiveQuery(
                sql: sql,
                columnLabels: labels,
                binds: binds,
                prefetch: prefetch,
                dbmsOutputEnabled: dbmsOutputEnabled,
                nextRowID: idx,
                iterator: iterator
            )
            let elapsed = Date.now.timeIntervalSince(start)
            applySuccess(labels: labels, rows: collected, sqlID: sqlID, dbmsOutput: dbmsOutput, elapsed: elapsed, sql: sql)
        } catch {
            applyFailure(AppDBError.from(error))
        }
    }

    private func applySuccess(labels: [String], rows: [DisplayRow], sqlID: String, dbmsOutput: String, elapsed: TimeInterval, sql: String) {
        objectWillChange.send()
        self.columnLabels = labels
        self.rows = rows
        self.sqlId = sqlID
        self.runningLog.append(RunningLogEntry(
            text: "sqlId: \(sqlID)\nElapsed: \(elapsed) sec.\n\(sql)" + (dbmsOutput.isEmpty ? "" : "\n********* DBMS_OUTPUT *********\n\(dbmsOutput)"),
            type: .info
        ))
        self.showingLog = !dbmsOutput.isEmpty
        self.isFailed = false
        self.dataHasChanged = true
        self.resultsController.isExecuting = false
    }

    private func applyFailure(_ error: AppDBError) {
        objectWillChange.send()
        self.isFailed = true
        self.showingLog = true
        self.runningLog.append(RunningLogEntry(text: error.description, type: .error))
        self.resultsController.isExecuting = false
    }

    func fetchMoreData() {
        guard let active = activeQuery else { return }
        objectWillChange.send()
        resultsController.isExecuting = true
        let limit = rowFetchLimit
        currentTask?.cancel()
        currentTask = Task { [weak self] in
            guard let self else { return }
            await self.pullMore(from: active, limit: limit)
        }
    }

    private func pullMore(from active: ActiveQuery, limit: Int) async {
        do {
            var collected: [DisplayRow] = []
            let cap = limit == -1 ? 10_000 : limit
            var count = 0
            let nextID = active.nextRowID
            let columnLabels = Array(active.columnLabels.dropFirst())
            while count < cap, let row = try await active.iterator.next() {
                if Task.isCancelled { break }
                collected.append(DisplayRowBuilder.make(from: row, id: nextID + count, columnLabels: columnLabels))
                count += 1
            }
            active.nextRowID += count
            objectWillChange.send()
            self.rows.append(contentsOf: collected)
            self.isFailed = false
            self.dataHasChanged = true
            self.resultsController.isExecuting = false
        } catch {
            applyFailure(AppDBError.from(error))
        }
    }

    func refreshData() {
        guard let active = activeQuery,
              let conn = resultsController.document?.conn else { return }
        currentSql = active.sql
        populateData(using: conn)
    }

    func getSQLCount() {
        guard let conn = resultsController.document?.conn else { return }
        let sql = "select count(1) CNT from (\(currentSql))"
        let binds = getBinds()
        let logger = oracleLogger
        objectWillChange.send()
        resultsController.isExecuting = true
        activeQuery = nil // Bug B: free the connection before a new execute.
        Task { [weak self] in
            guard let self else { return }
            do {
                let statement = BindValue.makeStatement(sql: sql, binds: binds)
                let rows = try await conn.execute(statement, logger: logger)
                var count = 0
                for try await row in rows {
                    if let cell = row.first, let value = try? cell.decode(Int.self) {
                        count = value
                    }
                }
                self.sqlCount = count
                self.isFailed = false
                self.resultsController.isExecuting = false
            } catch {
                self.applyFailure(AppDBError.from(error))
            }
        }
    }

    func displayError(_ error: AppDBError) {
        isFailed = true
        showingLog = true
        runningLog.append(RunningLogEntry(text: error.description, type: .error))
    }

    func clearError() {
        isFailed = false
        showingLog = false
    }

    func sort(by colName: String?, ascending: Bool) {
        guard let colName = colName else { return }
        guard let colIndex = columnLabels.firstIndex(of: colName), colIndex > 0 else { return }
        let dataIndex = colIndex - 1
        if ascending {
            rows.sort { DisplayRow.less(colIndex: dataIndex, lhs: $0, rhs: $1) }
        } else {
            rows.sort { DisplayRow.less(colIndex: dataIndex, lhs: $1, rhs: $0) }
        }
    }

    // MARK: - Explain plan / compile source

    func explainPlan(for sql: String, using conn: OracleConnection) {
        currentSql = "explain plan for " + sql
        objectWillChange.send()
        rows.removeAll()
        resultsController.isExecuting = true
        activeQuery = nil // Bug B: free the connection before a new execute.
        let logger = oracleLogger
        currentTask?.cancel()
        currentTask = Task { [weak self] in
            guard let self else { return }
            await self.runExplainPlan(conn: conn, explainSQL: self.currentSql, logger: logger)
        }
    }

    private func runExplainPlan(conn: OracleConnection, explainSQL: String, logger: Logging.Logger) async {
        let start = Date.now
        do {
            _ = try await conn.execute(OracleStatement(stringLiteral: explainSQL), logger: logger)
            let planRows = try await conn.execute(
                "select * from dbms_xplan.display(format => 'ALL')",
                logger: logger
            )
            let columns = DisplayRowBuilder.columnLabels(for: planRows.columns)
            var labels = columns
            labels.insert("#", at: 0)
            var collected: [DisplayRow] = []
            var idx = 0
            for try await row in planRows {
                if Task.isCancelled { break }
                collected.append(DisplayRowBuilder.make(from: row, id: idx, columnLabels: columns))
                idx += 1
            }
            let elapsed = Date.now.timeIntervalSince(start)
            self.applySuccess(labels: labels, rows: collected, sqlID: "", dbmsOutput: "", elapsed: elapsed, sql: explainSQL)
        } catch {
            self.applyFailure(AppDBError.from(error))
        }
    }

    func compileSource(for rsql: RunnableSQL, using conn: OracleConnection) {
        currentSql = rsql.sql
        objectWillChange.send()
        rows.removeAll()
        resultsController.isExecuting = true
        activeQuery = nil // Bug B: free the connection before a new execute.
        let logger = oracleLogger
        let compileSQL = rsql.sql
        let storedProc = rsql.storedProc
        currentTask?.cancel()
        currentTask = Task { [weak self] in
            guard let self else { return }
            await self.runCompile(conn: conn, compileSQL: compileSQL, storedProc: storedProc, logger: logger)
        }
    }

    private func runCompile(conn: OracleConnection, compileSQL: String, storedProc: StoredProc?, logger: Logging.Logger) async {
        let start = Date.now
        do {
            _ = try await conn.execute(OracleStatement(stringLiteral: compileSQL), logger: logger)
            let owner = storedProc?.owner ?? ""
            let name = storedProc?.name ?? ""
            let type = storedProc?.type ?? ""
            let query: OracleStatement = """
                select line, position, text from all_errors
                where owner = nvl(\(owner), user) and name = \(name) and type = \(type)
                order by line
                """
            let rows = try await conn.execute(query, logger: logger)
            let columns = DisplayRowBuilder.columnLabels(for: rows.columns)
            var labels = columns
            labels.insert("#", at: 0)
            var collected: [DisplayRow] = []
            var idx = 0
            for try await row in rows {
                if Task.isCancelled { break }
                collected.append(DisplayRowBuilder.make(from: row, id: idx, columnLabels: columns))
                idx += 1
            }
            let elapsed = Date.now.timeIntervalSince(start)
            if collected.isEmpty {
                let field = DisplayField(name: "Message", valueString: "Compiled Successfully", sortKey: .text("Compiled Successfully"))
                let labels = ["#", "Message"]
                let syntheticRow = DisplayRow(id: 0, fields: [field])
                self.applySuccess(labels: labels, rows: [syntheticRow], sqlID: "", dbmsOutput: "", elapsed: elapsed, sql: compileSQL)
            } else {
                self.applySuccess(labels: labels, rows: collected, sqlID: "", dbmsOutput: "", elapsed: elapsed, sql: compileSQL)
            }
        } catch {
            self.applyFailure(AppDBError.from(error))
        }
    }

    // MARK: - Export

    func export(to fileURL: URL, type: ExportType) {
        guard let conn = resultsController.document?.conn else { return }
        let sql = currentSql
        let binds = getBinds()
        let logger = oracleLogger
        objectWillChange.send()
        runningLog.append(RunningLogEntry(text: "Starting export to \(fileURL)", type: .info))
        showingLog = true
        activeQuery = nil // Bug B: free the connection before a new execute.
        Task { [weak self] in
            guard let self else { return }
            await self.performExport(conn: conn, sql: sql, binds: binds, fileURL: fileURL, type: type, logger: logger)
        }
    }

    private func performExport(
        conn: OracleConnection,
        sql: String,
        binds: [String: BindValue],
        fileURL: URL,
        type: ExportType,
        logger: Logging.Logger
    ) async {
        try? "".write(to: fileURL, atomically: true, encoding: .utf8)
        guard let fileHandle = try? FileHandle(forWritingTo: fileURL) else {
            log.error("Could not create file \(fileURL)")
            return
        }
        defer { try? fileHandle.close() }

        resultsController.isExecuting = true
        do {
            let statement = BindValue.makeStatement(sql: sql, binds: binds)
            let stream = try await conn.execute(
                statement,
                options: OracleOptions.with(prefetchRows: 10_000),
                logger: logger
            )
            let columns = DisplayRowBuilder.columnLabels(for: stream.columns)
            let bufferSize = 8 * 1024
            var buffer: [UInt8] = []
            buffer.reserveCapacity(bufferSize)
            var rowCnt = 0
            for try await row in stream {
                if Task.isCancelled { break }
                let display = DisplayRowBuilder.make(from: row, id: rowCnt, columnLabels: columns)
                rowCnt += 1
                let line = getLine(from: display, delimiter: type).appending("\n")
                buffer.append(contentsOf: line.utf8)
                if buffer.count >= bufferSize {
                    try? fileHandle.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
                if rowCnt % 1000 == 0 {
                    runningLog.append(RunningLogEntry(text: "\(rowCnt) rows exported", type: .info))
                }
            }
            if !buffer.isEmpty {
                try? fileHandle.write(contentsOf: buffer)
            }
            runningLog.append(RunningLogEntry(text: "Export completed; row count: \(rowCnt)", type: .info))
        } catch {
            let app = AppDBError.from(error)
            runningLog.append(RunningLogEntry(text: app.description, type: .error))
        }
        showingLog = true
        resultsController.isExecuting = false
    }

    func getLine(from row: DisplayRow, delimiter: ExportType) -> String {
        row.fields.map { field in
            switch delimiter {
            case .csv, .tsv:
                return "\"\(field.valueString)\""
            case .none:
                return field.valueString
            }
        }.joined(separator: delimiter.rawValue)
    }

    // MARK: - sqlId lookup

    static func fetchSqlID(on conn: OracleConnection, logger: Logging.Logger) async -> String {
        do {
            let rows = try await conn.execute(
                "select prev_sql_id from v$session where sid = sys_context('userenv','sid')",
                logger: logger
            )
            // Fully drain even though we only care about the first row —
            // returning inside the loop leaves the iterator to deinit
            // asynchronously, which races the next `execute(…)` on this
            // connection. See DBMSOutput.enable for the state-machine fatal
            // this prevents.
            var result = ""
            for try await sqlID in rows.decode(String.self) {
                if result.isEmpty { result = sqlID }
            }
            return result
        } catch {
            // No-op; sqlID is best-effort.
            return ""
        }
    }
}

enum ExportType: String, Sendable {
    case csv = ",", tsv = "\t", none = ""
}

/// Small wrapper for OracleNIO QueryOptions since we don't need a full builder.
enum OracleOptions {
    static func with(prefetchRows: Int) -> StatementOptions {
        var options = StatementOptions()
        options.arraySize = max(prefetchRows, 1)
        options.prefetchRows = max(prefetchRows, 2)
        return options
    }
}
