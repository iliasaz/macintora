//
//  SQLDocumentVM.swift
//  MacOra
//
//  Created by Ilia Sazonov on 10/4/21.
//

import SwiftUI
import UniformTypeIdentifiers
import Combine
import SwiftOracle
import Logging
import CodeEditor
import Network



extension UTType {
    static var macora: UTType {
        UTType(importedAs: "com.iliasazonov.macintora")
    }
}

public enum ConnectionStatus {
    case connected, disconnected, changing
}

public enum ConnectionHealthStatus {
    case ok, busy, lost, notConnected
}

class MainDocumentVM: ReferenceFileDocument, ObservableObject {
    
    typealias Snapshot = MainModel
    static var readableContentTypes: [UTType] { [.macora] }
    static var writableContentTypes: [UTType] { [.macora] }

    private(set) var resultsController: ResultsController?
    var model: MainModel
    private(set) var conn: Connection? // main connection
    private(set) var oraSession: OracleSession?
    
    @Published var connDetails: ConnectionDetails
    
    @Published var isConnected = ConnectionStatus.disconnected
    @Published var connectionHealth = ConnectionHealthStatus.notConnected
    @Published var dbName: String
    var pingTimer: Timer?
    
    var sbConnDetails: SBConnDetails {
        SBConnDetails(mainConnDetails: connDetails, mainSession: oraSession)
    }
    
    func snapshot(contentType: UTType) throws -> MainModel {
        model.connectionDetails = connDetails
        return model
    }
    
    func fileWrapper(snapshot: MainModel, configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(snapshot)
        let fileWrapper = FileWrapper(regularFileWithContents: data)
        return fileWrapper
    }

    required init(text: String = """
select user, systimestamp, sys_context('userenv','sid') sid, sys_context('userenv','con_name') pdb
  , sys_context('userenv','current_edition_name') edition, sys_context('userenv','instance') instance
from dual;\n\n
"""
    ) {
        let localModel = MainModel(text: text)
        model = localModel
        dbName = Constants.defaultDBName
        connDetails = localModel.connectionDetails
//        editorSelectionRange = "".startIndex..<"".endIndex
        resultsController = ResultsController(document: self)
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
//        log.debug("loading model: \(String(data: data, encoding: .utf8) ?? "" )")
        let localModel = try! JSONDecoder().decode(MainModel.self, from: data)
        self.model = localModel
//        log.debug("model loaded: \(localModel, privacy: .public)")
        dbName = localModel.connectionDetails.tns ?? ""
        connDetails = localModel.connectionDetails
//        editorSelectionRange = "".startIndex..<"".endIndex
        resultsController = ResultsController(document: self)
        if model.autoConnect ?? false {
            connect()
        }
    }
    
    // MARK: - Intent functions
    
    func connect() {
        isConnected = .changing
        Task.detached(priority: .background) { [self] in
            
            // we need a main stateful connection, and a pool of stateless sessions for navigation around the database
//            if conn == nil {
            let oracleService = OracleService(from_string: connDetails.tns)
            conn = Connection(service: oracleService, user: connDetails.username, pwd: connDetails.password, sysDBA: connDetails.connectionRole == .sysDBA)
//            }
            guard let conn = conn else {
                log.error("connection object is nil")
                await MainActor.run { isConnected = .disconnected }
                return
            }
            do {
                log.debug("Attempting to connect to \(self.connDetails.username, privacy: .public) @ \(self.connDetails.tns ?? Constants.nullValue, privacy: .public) as \(self.connDetails.connectionRole == .sysDBA ? "SysDBA" : "regular user", privacy: .public)")
                try conn.open()
                log.debug("connected to \(self.connDetails.tns, privacy: .public)")
                do { try conn.setFormat(fmtType: .date, fmtString: "YYYY-MM-DD HH24:MI:SS") }
                catch {
                    log.debug("setFormat failed: \(error.localizedDescription, privacy: .public)")
                    await resultsController?.displayError(error)
                }
                oraSession = MainDocumentVM.getOracleSession(for: conn)
            } catch DatabaseErrors.SQLError(let error) {
                log.error("connection failure: \(error.description, privacy: .public)")
                await resultsController?.displayError(error)
                await MainActor.run {
                    isConnected = .disconnected
//                    queryResults.isFailed = true
//                    queryResults.showingLog = true
//                    queryResults.runningLog.append(RunningLogEntry(text: error.description, type: .error))
                }
                return
            } catch {
                log.error("Other error: \(error.localizedDescription, privacy: .public)")
                await MainActor.run { isConnected = .disconnected }
                return
            }
            await MainActor.run {
                if conn.connected {
                    isConnected = .connected
                    connectionHealth = .ok
                    pingTimer = Timer.scheduledTimer(timeInterval: 30, target: self, selector: #selector(ping), userInfo: nil, repeats: true)
                    resultsController?.clearError()
                }
                else {isConnected = .disconnected}
            }
        }
    }
    
    func disconnect() {
        isConnected = .changing
        Task.detached(priority: .background) { [self] in
            guard let conn = conn else {
                log.error("connection doesn't exist")
                return
            }
            self.resultsController?.results["current"]?.currentCursor = nil
            conn.close()
            oraSession = nil
            self.pingTimer?.invalidate() // stop scheduled pings
            await MainActor.run {
                if !conn.connected {
                    isConnected = .disconnected
                    connectionHealth = .notConnected
                    log.debug("disconnected from \(self.connDetails.tns, privacy: .public)")
                }
            }
        }
    }
    
    static func getOracleSession(for conn: Connection?) -> OracleSession? {
        guard let conn = conn else {
            log.error("connection doesn't exist")
            return nil
        }
        var oraSession: OracleSession?
        do {
            let cursor = try conn.cursor()
            let sql = "select sid, serial#, to_number(sys_context('userenv','instance')) instance from v$session where sid = sys_context('userenv','sid')"
            try cursor.execute(sql, enableDbmsOutput: false)
            guard let row = cursor.fetchOneSwifty() else {return nil}
            oraSession = OracleSession(sid: row["SID"]!.int!, serial: row["SERIAL#"]!.int!, instance: row["INSTANCE"]!.int!)
            log.debug("received Oracle session details")
        } catch {
            log.error("\(error.localizedDescription, privacy: .public)")
        }
        return oraSession
    }
    
    /// Here we determine the SQL under the current cursor position
    func getCurrentSql(for editorSelectionRange: Range<String.Index>) -> String? {
        let regexOptions: NSRegularExpression.Options = [.anchorsMatchLines]
        var ret: String = ""
        if editorSelectionRange.lowerBound != editorSelectionRange.upperBound { // user selected something, we should honor that
            ret = String(model.text[editorSelectionRange]).trimmingCharacters(in: ["\n"])
        } else {
            var firstIndex = model.text.startIndex
            var lastIndex = model.text.endIndex
            var currentIndex = editorSelectionRange.lowerBound
            if firstIndex == lastIndex { return "" }
            
            log.sqlparse.debug("original current index: \(currentIndex.utf16Offset(in: self.model.text))")
            let semicolonToTheLeftIndex = model.text.firstIndex(of: ";", before: currentIndex) ?? firstIndex
            let NLToTheLeftIndex = model.text.firstIndex(of: "\n", before: currentIndex) ?? firstIndex
            if semicolonToTheLeftIndex > NLToTheLeftIndex {
                currentIndex = semicolonToTheLeftIndex
                lastIndex = semicolonToTheLeftIndex
                log.sqlparse.debug("new current index \(currentIndex.utf16Offset(in: self.model.text))")
            }
            
            let semiColonPattern = #";.*\n"#
            let regex = try! NSRegularExpression(pattern: semiColonPattern, options: regexOptions)
            
            let rangeBefore = regex.matches(in: model.text, range: NSRange(firstIndex..<currentIndex, in: model.text)).last
            let rangeAfter = regex.firstMatch(in: model.text, range: NSRange(currentIndex..<lastIndex, in: model.text))
            
            log.sqlparse.debug("*************************")
            if let range = rangeBefore {
                log.sqlparse.debug("rangeBefore: lowerBound: \(range.range.lowerBound) upperBound: \(range.range.upperBound) length: \(range.range.length)")
                firstIndex = Range(range.range, in: model.text)!.upperBound
            } else {
                log.sqlparse.debug("before not found")
            }

            if let range = rangeAfter {
                log.sqlparse.debug("rangeAfter: lowerBound: \(range.range.lowerBound) upperBound: \(range.range.upperBound) length: \(range.range.length)")
                lastIndex = Range(range.range, in: model.text)!.lowerBound
            } else {
                // the pattern is not found, but there may be a single line with a ; in it
                let semicolonToTheRightIndex = model.text.firstIndex(of: ";", after: currentIndex) ?? firstIndex
                if semicolonToTheRightIndex > firstIndex {
                    lastIndex = semicolonToTheRightIndex
                } else {
                    log.sqlparse.debug("after not found")
                }
            }
            
            log.sqlparse.debug("sql candidate range is: \(firstIndex.utf16Offset(in: self.model.text)), \(lastIndex.utf16Offset(in: self.model.text))")
            var sqlCandidate = String(model.text[firstIndex ..< lastIndex])
            // remove empty lines, lines starting with a full line comment, and lines with a single slash
            var sqlCandidateLines = sqlCandidate.split(separator: "\n").compactMap { String($0) }
            var toRemove = IndexSet()
            for (index, l) in sqlCandidateLines.enumerated() {
                if l.starts(with: "--") {
                    log.sqlparse.debug("line at \(index) starts with comment: \(l)")
                    toRemove.insert(index)
                }
                if l.replacingOccurrences(of: " ", with: "") == "/" {
                    log.sqlparse.debug("line at \(index) contains only a slash")
                    toRemove.insert(index)
                }
            }
            log.sqlparse.debug("removing lines at \(toRemove)")
            sqlCandidateLines.remove(atOffsets: toRemove)
            // replace exec with call in single line commands
            if sqlCandidateLines.count == 1 && sqlCandidateLines[0].starts(with: "exec ") {
                sqlCandidateLines[0] = sqlCandidateLines[0].replacingOccurrences(of: "exec ", with: "call ")
            }
            sqlCandidate = sqlCandidateLines.joined(separator: "\n")
            log.sqlparse.debug("sql:==\(sqlCandidate)==")
            ret = sqlCandidate
        }
        return ret.isEmpty ? nil : ret
    }
    
    func runCurrentSQL(for editorSelectionRange: Range<String.Index>) {
        guard let sql = getCurrentSql(for: editorSelectionRange) else { resultsController?.isExecuting = false; return }
        resultsController?.runSQL(RunnableSQL(sql: sql))
    }
    
    func stopRunningSQL() {
        if !(resultsController?.isExecuting ?? false) {
            log.debug("nothing to stop")
            return
        }
        guard let conn = self.conn, self.isConnected == .connected else {
            log.error("connection doesn't exist")
            isConnected = .disconnected
            resultsController?.isExecuting = false
            return
        }
        Task.detached(priority: .background) {
            log.debug("attempting to stop current SQL")
            conn.break()
            self.resultsController?.results["current"]?.currentCursor = nil
            log.debug("done attempting to stop current SQL")
            await MainActor.run {
                self.resultsController?.isExecuting = false
            }
        }
    }
    
    func explainPlan(for editorSelectionRange: Range<String.Index>) {
        resultsController?.isExecuting = true
        guard let conn = conn, conn.connected else {
            log.error("connection doesn't exist")
            isConnected = .disconnected
            resultsController?.isExecuting = false
            return
        }
    
        guard let sql = getCurrentSql(for: editorSelectionRange) else { resultsController?.isExecuting = false; return }
        resultsController?.explainPlan(for: sql)
        resultsController?.isExecuting = false
    }
    
    func compileSource(for editorSelectionRange: Range<String.Index>) {
        let sql: String
        if editorSelectionRange.isEmpty { sql = model.text }
        else { sql = String(model.text[editorSelectionRange]) }
        let runnableSQL = RunnableSQL(sql: sql)
        guard runnableSQL.isStoredProc else { return }
        guard let conn = conn, conn.connected else {
            log.error("connection doesn't exist")
            isConnected = .disconnected
            return
        }
        resultsController?.isExecuting = true
        resultsController?.compileSource(for: runnableSQL)
        resultsController?.isExecuting = false
    }
    
    func refreshQueryResults() async {
        return
        
        guard let conn = conn, conn.connected else {
            log.error("connection doesn't exist")
            isConnected = .disconnected
            return
        }
    }
    
    func newDocument(from editorSelectionRange: Range<String.Index>) -> URL? {
        var text = ""
        // grab selected text or current SQL
        if editorSelectionRange.lowerBound != editorSelectionRange.upperBound { // user selected something, we should honor that
            text = String(model.text[editorSelectionRange])
        } else {
            text = (getCurrentSql(for: editorSelectionRange) ?? "") + "\n"
        }
        
        // create a new document, copy properties from the current one
        var newModel = MainModel(text: text)
        newModel.connectionDetails = self.model.connectionDetails
        newModel.preferences = self.model.preferences
//        newModel.quickFilterPrefs = self.model.quickFilterPrefs
        // connect automatically?
        if isConnected == .connected {
            newModel.autoConnect = true
        }
        // save a temp file
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let temporaryFilename = "\(UUID().uuidString).macintora"
        let temporaryFileURL = temporaryDirectoryURL.appendingPathComponent(temporaryFilename)
        log.debug("temp file path: \(temporaryFileURL.path, privacy: .public)")
        
        do {
            let data = try JSONEncoder().encode(newModel)
            if (FileManager.default.createFile(atPath: temporaryFileURL.path, contents: data, attributes: nil)) {
                log.debug("File created successfully.")
            } else {
                log.error("File not created - \(temporaryFileURL.path, privacy: .public)")
                return nil
            }
        } catch {
            log.error("File write failed: \(error.localizedDescription, privacy: .public), \(temporaryFileURL.path, privacy: .public)")
            return nil
        }
        return temporaryFileURL
    }
    
    // format selected SQL or current SQL
    func format(of editorSelectionRange: Range<String.Index>) {
        var text = ""
        if editorSelectionRange.lowerBound != editorSelectionRange.upperBound { // user selected something, we'll format that
            text = String(model.text[editorSelectionRange])
        } else {
            text = getCurrentSql(for: editorSelectionRange) ?? ""
        }
        guard !text.isEmpty else { return }
        let formatter = Formatter()
        log.debug(">>>>>>> sql text: \n \(text) \n -------------")
        Task.detached(priority: .background) { [self, text] in
            let formattedText = await formatter.formatSource(name: UUID().uuidString, text: text)
            await MainActor.run {
                self.objectWillChange.send()
                self.model.text = self.model.text.replacingCharacters(in: editorSelectionRange, with: formattedText)
            }
        }
    }
    
    @objc func ping() {
        log.debug("in \(#function, privacy: .public)")
        if (self.resultsController?.isExecuting ?? false) || self.isConnected == .disconnected {
            log.debug("skipping ping")
            return
        }
        Task.detached(priority: .background) {
            guard let conn = self.conn, self.isConnected == .connected else {
                log.debug("ping: not connected")
                if self.connectionHealth != .notConnected {
                    await MainActor.run { self.connectionHealth = .notConnected }
                }
                return
            }
            let pingResult = conn.ping()
            if pingResult {
                log.debug("ping: ok")
                if self.connectionHealth != .ok {
                    await MainActor.run { self.connectionHealth = .ok }
                }
            } else {
                log.debug("ping: lost connection")
                if self.connectionHealth == .ok {
                    await MainActor.run { self.connectionHealth = .lost }
                }
            }
        }
    }
    
//    func backgroundAction() {
//        queryResults.isExecuting = true
//        self.objectWillChange.send()
//        Task {
//            await MainActor.run {
//                self.queryResults.isExecuting = false
//                self.objectWillChange.send()
//            }
//        }
//    }

}
