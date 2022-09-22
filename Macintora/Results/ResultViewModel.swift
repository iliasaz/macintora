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
                    return NSAttributedString(string: "--------------------\n" + element.timestamp.ISO8601Format() + "\n" + element.text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12.0, weight: .regular)])
                }
            }.joined(with: "\n")
            
//            let s = NSMutableAttributedString(string: "test", attributes: [.foregroundColor: NSColor.red])
        } set { }
    }
    
    var currentSql: String = ""
    var sqlId: String = ""
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
        resultsController.isExecuting = true
        Task.detached(priority: .background) { [self] in
            let result = await queryData(for: currentSql, using: conn, maxRows: rowFetchLimit, showDbmsOutput: enabledDbmsOutput, binds: getBinds(), prefetchSize: queryPrefetchSize)
            await MainActor.run {
                updateViews(with: result)
            }
        }
    }
    
    func updateViews(with result: Result<([String], [SwiftyRow], String, String), Error>) {
        objectWillChange.send()
        switch result {
            case .success(let (resultColumns, resultRows, sqlId, dbmsOutput)):
                self.columnLabels = resultColumns
                self.rows = resultRows
                runningLog.append(RunningLogEntry(text: "sqlId: \(sqlId)\n" + currentSql + (dbmsOutput.isEmpty ? "" : "\n********* DBMS_OUTPUT *********\n\(dbmsOutput)"), type: .info))
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
        log.debug("end of refreshData")
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
        guard let colIndex = columnLabels.firstIndex(of: colName) else { return }
        if ascending {
            rows.sort(by: {SwiftyRow.less(colIndex: colIndex-1, lhs: $0, rhs: $1)} ) // account for row number!
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
            let explainStatus = await queryData(for: currentSql, using: conn, maxRows: -1)
            await MainActor.run {
                updateViews(with: explainStatus)
            }
            switch explainStatus {
                case .success( _):
                    let explainResult = await queryData(for: "select * from dbms_xplan.display(format => 'ALL')", using: conn, maxRows: -1, prefetchSize: 1000)
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
            let compilationStatus = await queryData(for: currentSql, using: conn, maxRows: -1)
            await MainActor.run {
                updateViews(with: compilationStatus)
            }
            switch compilationStatus {
                case .success( _):
                    var binds = [String: BindVar]()
                    binds[":owner"] = BindVar(rsql.storedProc?.owner ?? "")
                    binds[":name"] = BindVar(rsql.storedProc?.name ?? "")
                    binds[":type"] = BindVar(rsql.storedProc?.type ?? "")
                    let compilationResult = await queryData(for: "select line, position, text from all_errors where owner = nvl(:owner, user) and name = :name and type = :type", using: conn, maxRows: -1, binds: binds, prefetchSize: 1000)
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
}

