//
//  TableModel.swift
//  TabApp
//
//  Created by Ilia on 10/25/21.
//

import Foundation
import Combine
import SwiftOracle
import SwiftUI

enum RunningLogEntryType {
    case info, error
}

struct RunningLogEntry {
    let text: String
    let type: RunningLogEntryType
    let timestamp = Date()
}

//actor ResultData {
//    func queryData(for sql:String, using conn:Connection, maxRows: Int, showDbmsOutput: Bool = false, binds: [String: BindVar] = [:], prefetchSize: Int = 200) async -> Result<([String], [SwiftyRow], String, String), Error> {
//        let result: Result<([String], [SwiftyRow], String, String), Error>
//        var rows = [SwiftyRow]()
//        var columnLabels = [String]()
//        do {
//            let cursor = try conn.cursor()
//            try cursor.execute(sql, params: binds, prefetchSize: prefetchSize, enableDbmsOutput: showDbmsOutput)
//            let sqlId = cursor.sqlId
//            let dbmsOuput = cursor.dbmsOutputContent
//            columnLabels = cursor.getColumnLabels()
//            rows = [SwiftyRow]()
//            var rowCnt = 0
//            while let row = cursor.nextSwifty(withStringRepresentation: true), rowCnt < (maxRows == -1 ? 10000 : maxRows) {
//                rows.append(row)
//                rowCnt += 1
//            }
//            columnLabels.insert("#", at: 0)
//            result = .success((columnLabels, rows, sqlId, dbmsOuput))
//            log.debug("data loaded, rows.count: \(rows.count)")
//        } catch DatabaseErrors.SQLError (let error) {
//            log.error("\(error.description, privacy: .public)")
//            result = .failure(error)
//        } catch {
//            log.error("\(error.localizedDescription, privacy: .public)")
//            result = .failure(error)
//        }
//        return result
//    }
//}

public class ResultViewModel: ObservableObject {
    @AppStorage("rowFetchLimit") var rowFetchLimit: Int = 200
    @AppStorage("queryPrefetchSize") private var queryPrefetchSize: Int = 200
    
    var rows = [SwiftyRow]()
    var columnLabels = [String]()
    var isFailed = false
    
    @Published var autoColWidth = true { willSet {
        objectWillChange.send()
        dataHasChanged = true
    }}
    
    @Published var showingLog = false
    @Published var showingBindVarInputView = false
    @Published var sqlCount: Int = 0
    
    var bindVarVM = BindVarInputVM()
    private(set) var resultsController: ResultsController
    var dataHasChanged = false
    
    init(parent: ResultsController) {
        resultsController = parent
    }
    
    var enabledDbmsOutput = true
    var runningLog: [RunningLogEntry] = []
    var runningLogStr: NSAttributedString {
        get {
            runningLog.reversed().map { element -> NSAttributedString in
                if element.type == .error {
                    return NSAttributedString(string: "--------------------\n" + element.timestamp.ISO8601Format() + "\n" + element.text, attributes: [.foregroundColor: NSColor.red])
                } else {
                    return NSAttributedString(string: "--------------------\n" + element.timestamp.ISO8601Format() + "\n" + element.text, attributes: [.foregroundColor: NSColor.textColor, .font: NSFont.monospacedSystemFont(ofSize: 12.0, weight: .regular)])
                }
            }.joined(with: "\n")
            
//            let s = NSMutableAttributedString(string: "test", attributes: [.foregroundColor: NSColor.red])
        } set { }
    }
    
    var currentSql: String = ""
    var sqlId: String = ""
    var currentCursor: Cursor?

//    var data = ResultData()
    
    // Test data
    func init_preview(_ numRows: Int, _ numCols: Int) {
        columnLabels = (0..<numCols).map { "Column \($0)" }
        rows = (0..<numRows).map { rowNum in
            return SwiftyRow(withSwiftyFields: columnLabels.enumerated().map { colNum, colLabel in
                SwiftyField(name: colLabel, type: .string, index: colNum, value: String("super very long long long long long long Value \(rowNum) - \(colNum)"), isNull: false)
            } )
        }
    }
    
    func getBinds() -> [String : BindVar] {
        bindVarVM.bindVars.reduce(into: [String: BindVar]()) {
            switch $1.type {
                case .text: $0[$1.name] = BindVar($1.textValue)
                case .null: $0[$1.name] = BindVar("")
                case .date: $0[$1.name] = $1.dateValue == nil ? BindVar("") : BindVar($1.dateValue!)
                case .int: $0[$1.name] = $1.intValue == nil ? BindVar("") : BindVar($1.intValue!)
                case .decimal: $0[$1.name] = $1.decValue == nil ? BindVar("") : BindVar($1.decValue!)
            }
        }
    }
    
    func populateData2(using conn: Connection) {
        objectWillChange.send()
        rows.removeAll()
        sqlCount = 0
        resultsController.isExecuting = true
        Task.detached(priority: .background) { [self] in
            if currentCursor == nil {
                do {
                    currentCursor = try conn.cursor()
                } catch {
                    log.error("\(error.localizedDescription, privacy: .public)")
                    await MainActor.run {
                        resultsController.isExecuting = false
                        isFailed = true
                        showingLog = true
                        runningLog.append(RunningLogEntry(text: (error as! DatabaseError).description, type: .error))
                    }
                    return
                }
            }
            let start = Date.now
            let result = await queryData(for: currentSql, using: currentCursor!, maxRows: rowFetchLimit, showDbmsOutput: enabledDbmsOutput, binds: getBinds(), prefetchSize: queryPrefetchSize)
            let elapsed = Date.now.timeIntervalSince(start)
            await MainActor.run {
                updateViews(with: result, elapsedTime: elapsed)
            }
        }
    }
    
    func updateViews(with result: Result<([String], [SwiftyRow], String, String), Error>, elapsedTime: TimeInterval = TimeInterval(0)) {
        objectWillChange.send()
        switch result {
            case .success(let (resultColumns, resultRows, sqlId, dbmsOutput)):
                self.columnLabels = resultColumns
                self.rows = resultRows
                runningLog.append(RunningLogEntry(text: "sqlId: \(sqlId)\n" + "Elapsed: \(elapsedTime) sec.\n" + currentSql + (dbmsOutput.isEmpty ? "" : "\n********* DBMS_OUTPUT *********\n\(dbmsOutput)"), type: .info))
                self.sqlId = sqlId
                showingLog = !dbmsOutput.isEmpty
                isFailed = false
                dataHasChanged = true
            case .failure(let error):
                isFailed = true
                showingLog = true
                runningLog.append(RunningLogEntry(text: (error as! DatabaseError).description, type: .error))
        }
        resultsController.isExecuting = false
        log.debug("end of updateViews, row count: \(self.rows.count)")
    }
    
    func setSQLCount(with result: Result<([String], [SwiftyRow], String, String), Error>) {
        objectWillChange.send()
        switch result {
            case .success(let (_, resultRows, _, _)):
                self.sqlCount = resultRows[0]["CNT"]!.int ?? 0
                isFailed = false
            case .failure(let error):
                isFailed = true
                showingLog = true
                runningLog.append(RunningLogEntry(text: (error as! DatabaseError).description, type: .error))
        }
        resultsController.isExecuting = false
        log.debug("end of setSQLCount")
    }
    
    func fetchMoreData() {
        objectWillChange.send()
        resultsController.isExecuting = true
        Task.detached(priority: .background) { [self] in
            let result = await queryMoreData(for: self.currentCursor, maxRows: rowFetchLimit)
            await MainActor.run {
                objectWillChange.send()
                switch result {
                    case .success(let moreRows):
                        self.rows.append(contentsOf: moreRows)
                        isFailed = false
                        dataHasChanged = true
                    case .failure(let error):
                        isFailed = true
                        showingLog = true
                        runningLog.append(RunningLogEntry(text: (error as! DatabaseError).description, type: .error))
                }
                resultsController.isExecuting = false
            }
        }
    }
    
    func getSQLCount() {
        guard let conn = self.resultsController.document?.conn else { return }
        let sql = "select count(1) CNT from (\(currentSql))"
        objectWillChange.send()
        resultsController.isExecuting = true
        Task.detached(priority: .background) { [self] in
            do {
                // discardable cursor here
                let cursor = try conn.cursor()
                let result = await queryData(for: sql, using: cursor, maxRows: 1, showDbmsOutput: false, binds: getBinds(), prefetchSize: 1)
                await MainActor.run {
                    setSQLCount(with: result)
                }
            } catch {
                log.error("\(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    resultsController.isExecuting = false
                    isFailed = true
                    showingLog = true
                    runningLog.append(RunningLogEntry(text: (error as! DatabaseError).description, type: .error))
                }
                return
            }
        }
    }
    
    @MainActor
    func displayError(_ error: Error) {
        isFailed = true
        showingLog = true
        runningLog.append(RunningLogEntry(text: (error as! DatabaseError).description, type: .error))
    }
    
    @MainActor
    func clearError() {
        isFailed = false
        showingLog = false
    }
    
    func promptForBindsAndExecute(for runnableSQL: RunnableSQL, using conn: Connection) {
        log.debug("in ResultViewmodel.executeSQL")
        currentSql = runnableSQL.sql
        if runnableSQL.bindNames.isEmpty {
            if showingBindVarInputView {showingBindVarInputView = false}
//            bindVarVM.bindVars.removeAll()
            populateData2(using: conn)
        } else {
            currentSql = runnableSQL.sql
            // try to merge the new bind vars with the existing ones
            bindVarVM = BindVarInputVM(from: bindVarVM, bindNames: runnableSQL.bindNames)
            if !showingBindVarInputView {showingBindVarInputView = true}
        }
    }
    
    func runCurrentSQL(using conn: Connection) {
        populateData2(using: conn)
    }
    
    func sort(by colName: String?, ascending: Bool) {
        guard let colName = colName else { return }
        guard let colIndex = columnLabels.firstIndex(of: colName), colIndex > 0 else { return } // account for row number!
        if ascending {
            rows.sort(by: {SwiftyRow.less(colIndex: colIndex-1, lhs: $0, rhs: $1)} )
        } else {
            rows.sort(by: {SwiftyRow.less(colIndex: colIndex-1, lhs: $1, rhs: $0)} )
        }
    }
    
    func explainPlan(for sql: String, using conn: Connection) {
        currentSql = "explain plan for " + sql
        objectWillChange.send()
        rows.removeAll()
        resultsController.isExecuting = true
        Task.detached(priority: .background) { [self] in
            if currentCursor == nil {
                do {
                    currentCursor = try conn.cursor()
                } catch {
                    log.error("\(error.localizedDescription, privacy: .public)")
                    await MainActor.run {
                        resultsController.isExecuting = false
                        isFailed = true
                        showingLog = true
                        runningLog.append(RunningLogEntry(text: (error as! DatabaseError).description, type: .error))
                    }
                    return
                }
            }
            let explainStatus = await queryData(for: currentSql, using: currentCursor!, maxRows: -1)
            await MainActor.run {
                updateViews(with: explainStatus)
            }
            switch explainStatus {
                case .success( _):
                    let explainResult = await queryData(for: "select * from dbms_xplan.display(format => 'ALL')", using: currentCursor!, maxRows: -1, prefetchSize: 1000)
                    await MainActor.run {
                        updateViews(with: explainResult)
                    }
                default: return
            }
        }
    }
    
    func compileSource(for rsql: RunnableSQL, using conn: Connection) {
        currentSql = rsql.sql
        objectWillChange.send()
        rows.removeAll()
        resultsController.isExecuting = true
        Task.detached(priority: .background) { [self] in
            if currentCursor == nil {
                do {
                    currentCursor = try conn.cursor()
                } catch {
                    log.error("\(error.localizedDescription, privacy: .public)")
                    await MainActor.run {
                        resultsController.isExecuting = false
                        isFailed = true
                        showingLog = true
                        runningLog.append(RunningLogEntry(text: (error as! DatabaseError).description, type: .error))
                    }
                    return
                }
            }
            let compilationStatus = await queryData(for: currentSql, using: currentCursor!, maxRows: -1)
            await MainActor.run {
                updateViews(with: compilationStatus)
            }
            switch compilationStatus {
                case .success( _):
                    var binds = [String: BindVar]()
                    binds[":owner"] = BindVar(rsql.storedProc?.owner ?? "")
                    binds[":name"] = BindVar(rsql.storedProc?.name ?? "")
                    binds[":type"] = BindVar(rsql.storedProc?.type ?? "")
                    let compilationResult = await queryData(for: "select line, position, text from all_errors where owner = nvl(:owner, user) and name = :name and type = :type order by line", using: currentCursor!, maxRows: -1, binds: binds, prefetchSize: 1000)
                    // if there are no errors, we want to show a message "Compiled Successfully" instead of a blank grid
                    let tweakedCompilationResult: Result<([String], [SwiftyRow], String, String), Error>
                    switch compilationResult {
                        case .success(let (_, resultRows, _, _)):
                            if resultRows.count == 0 {
                                // handcrafting the result
                                tweakedCompilationResult = .success((["#", "Message"], [SwiftyRow(withSwiftyFields: [SwiftyField(name: "Message", type: .string, index: 0, value: String("Compiled Successfully"), isNull: false, valueString: "Compiled Successfully")])], "", ""))
                            } else {
                                tweakedCompilationResult = compilationResult
                            }
                        case .failure(_): tweakedCompilationResult = compilationResult
                    }
                    await MainActor.run {
                        updateViews(with: tweakedCompilationResult)
                    }
                default: return
            }
        }
    }
    
    func queryData(for sql:String, using cursor: Cursor, maxRows: Int, showDbmsOutput: Bool = false, binds: [String: BindVar] = [:], prefetchSize: Int = 200) async -> Result<([String], [SwiftyRow], String, String), Error> {
        let result: Result<([String], [SwiftyRow], String, String), Error>
        var rows = [SwiftyRow]()
        var columnLabels = [String]()
        do {
            try cursor.execute(sql, params: binds, prefetchSize: prefetchSize, enableDbmsOutput: showDbmsOutput)
            let sqlId = cursor.sqlId
            let dbmsOuput = cursor.dbmsOutputContent
            columnLabels = cursor.getColumnLabels()
            rows = [SwiftyRow]()
            var rowCnt = 0
            while rowCnt < (maxRows == -1 ? 10000 : maxRows), let row = cursor.nextSwifty(withStringRepresentation: true) {
                log.debug("row#: \(rowCnt), row: \(row)")
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
    
    func queryMoreData(for cursor: Cursor?, maxRows: Int) async -> Result<[SwiftyRow], Error> {
        log.debug("in queryMoreData")
        guard let cursor = cursor else { log.debug("no active cursor"); return .success([]) }
        let result: Result<[SwiftyRow], Error>
        var rows = [SwiftyRow]()
        var rowCnt = 0
        while rowCnt < (maxRows == -1 ? 10000 : maxRows), let row = cursor.nextSwifty(withStringRepresentation: true) {
            print("rowCnt: \(rowCnt), row: \(row)")
            rows.append(row)
            rowCnt += 1
        }
        result = .success(rows)
        log.debug("more data loaded, rows.count: \(rows.count)")
        return result
    }
    
    func refreshData() {
        log.debug("in refreshData()")
        guard let cursor = currentCursor else { return }
        objectWillChange.send()
        resultsController.isExecuting = true
        rows.removeAll()
        sqlCount = 0
        Task.detached(priority: .background) { [self] in
            let result: Result<([String], [SwiftyRow], String, String), Error>
            var rows = [SwiftyRow]()
            do {
                try cursor.refreshData(prefetchSize: rowFetchLimit)
                rows = [SwiftyRow]()
                var rowCnt = 0
                while rowCnt < (rowFetchLimit == -1 ? 10000 : rowFetchLimit), let row = cursor.nextSwifty(withStringRepresentation: true) {
                    print("rowCnt: \(rowCnt), row: \(row)")
                    rows.append(row)
                    rowCnt += 1
                }
                result = .success((self.columnLabels, rows, self.sqlId, ""))
                log.debug("data loaded, rows.count: \(rows.count)")
            } catch DatabaseErrors.SQLError (let error) {
                log.error("\(error.description, privacy: .public)")
                result = .failure(error)
            } catch {
                log.error("\(error.localizedDescription, privacy: .public)")
                result = .failure(error)
            }
            await MainActor.run {
                log.debug("updating views with result")
                updateViews(with: result)
                log.debug("finished refreshData()")
            }
        }
    }
    
    func export(to fileURL: URL, type: ExportType) {
        log.debug("in export()")
        guard let cursor = currentCursor else { return }
        objectWillChange.send()
        runningLog.append(RunningLogEntry(text: "Starting export to \(fileURL)", type: .info))
        showingLog = true
        Task.detached(priority: .background) { [self] in
            var rowCnt = 0
            // ensure file exists and is empty
            try? "".write(to: fileURL, atomically: true, encoding: .utf8)
            guard let fileHandle = try? FileHandle(forWritingTo: fileURL) else {
                log.error("Could not create file \(fileURL)")
                return
            }
            
            defer {
                fileHandle.closeFile()
            }
            
            let bufferSize = 8*1024
            var buffer: [UInt8] = []
            buffer.reserveCapacity(bufferSize)
            // Write the final buffer
            try? fileHandle.write(contentsOf: buffer)
            await MainActor.run {
                resultsController.isExecuting = true
            }
            do {
                try cursor.refreshData(prefetchSize: 10_000)
                while let row = cursor.nextSwifty(withStringRepresentation: true) {
                    rowCnt += 1
                    let s = getLine(from: row, delimiter: type).appending("\n")
                    // bufferred writing
                    buffer.append(contentsOf: s.utf8)
                    if buffer.count >= bufferSize {
                        try? fileHandle.write(contentsOf: buffer)
                        buffer.removeAll(keepingCapacity: true)
                    }
                    // log
                    if rowCnt%1000 == 0 {
                        runningLog.append(RunningLogEntry(text: "\(rowCnt) rows ezported", type: .info))
                    }
                }
                // remainder
                if buffer.count >= 0 {
                    try? fileHandle.write(contentsOf: buffer)
                }
            } catch DatabaseErrors.SQLError (let error) {
                log.error("\(error.description, privacy: .public)")
                runningLog.append(RunningLogEntry(text: error.text, type: .error))
                await MainActor.run {
                    showingLog = true
                    resultsController.isExecuting = false
                }
            } catch {
                log.error("\(error.localizedDescription, privacy: .public)")
                runningLog.append(RunningLogEntry(text: error.localizedDescription, type: .error))
                await MainActor.run {
                    showingLog = true
                    resultsController.isExecuting = false
                }
            }
            runningLog.append(RunningLogEntry(text: "Export completed; row count: \(rowCnt)", type: .info))
            await MainActor.run {
                showingLog = true
                resultsController.isExecuting = false
            }
        }
    }
    
    func getLine(from row: SwiftyRow, delimiter: ExportType) -> String {
        let s = (row.fields.map { value in
            switch delimiter {
                case .csv, .tsv:
                    return "\"\(value.valueString)\""
                case .none :
                    return value.valueString
            }
        }).joined(separator: delimiter.rawValue)
        return s
    }
}

enum ExportType: String {
    case csv = ",", tsv = "\t", none = ""
}
