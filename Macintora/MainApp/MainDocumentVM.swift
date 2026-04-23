@preconcurrency import SwiftUI
import UniformTypeIdentifiers
import Combine
import Logging
@preconcurrency import CodeEditor
import Network
import OracleNIO
import NIOCore

extension UTType {
    static var macora: UTType {
        UTType(importedAs: "com.iliasazonov.macintora")
    }
}

// ReferenceFileDocument conformance lives outside the @MainActor class so the
// nonisolated protocol methods can satisfy the protocol witnesses.
extension MainDocumentVM: @preconcurrency ReferenceFileDocument {}

nonisolated public enum ConnectionStatus: Sendable {
    case connected, disconnected, changing
}

nonisolated public enum ConnectionHealthStatus: Sendable {
    case ok, busy, lost, notConnected
}

@MainActor
final class MainDocumentVM: ObservableObject {
    typealias Snapshot = MainModel
    static var readableContentTypes: [UTType] { [.macora] }
    static var writableContentTypes: [UTType] { [.macora] }

    private(set) var resultsController: ResultsController?
    var model: MainModel
    private(set) var conn: OracleConnection?
    @Published var mainConnection: MainConnection
    @Published var isConnected = ConnectionStatus.disconnected
    @Published var connectionHealth = ConnectionHealthStatus.notConnected
    @Published var dbName: String
    private var pingTask: Task<Void, Never>?

    private let oracleLogger: Logging.Logger = {
        var logger = Logging.Logger(label: "com.iliasazonov.macintora.oracle")
        logger.logLevel = .notice
        return logger
    }()

    func snapshot(contentType: UTType) throws -> MainModel {
        model.connectionDetails = mainConnection.mainConnDetails
        return model
    }

    nonisolated func fileWrapper(snapshot: MainModel, configuration: WriteConfiguration) throws -> FileWrapper {
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
        mainConnection = MainConnection(mainConnDetails: localModel.connectionDetails)
        resultsController = ResultsController(document: self)
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let localModel = try JSONDecoder().decode(MainModel.self, from: data)
        self.model = localModel
        dbName = localModel.connectionDetails.tns
        mainConnection = MainConnection(mainConnDetails: localModel.connectionDetails)
        resultsController = ResultsController(document: self)
        if model.autoConnect ?? false {
            connect()
        }
    }

    // MARK: - Intent functions

    func connect() {
        isConnected = .changing
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
            log.error("connection configuration failed: \(error.localizedDescription, privacy: .public)")
            await resultsController?.displayError(AppDBError.from(error))
            isConnected = .disconnected
            return
        }
        log.debug("Attempting to connect to \(details.username, privacy: .public)@\(details.tns, privacy: .public) as \(details.connectionRole == .sysDBA ? "SysDBA" : "regular user", privacy: .public)")
        do {
            let newConn = try await OracleConnection.connect(
                on: OracleEventLoopGroup.shared.next(),
                configuration: configuration,
                id: Int.random(in: 1...Int.max),
                logger: logger
            )
            self.conn = newConn
            log.debug("connected to \(details.tns, privacy: .public)")
            try? await newConn.execute(
                "ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD HH24:MI:SS'",
                logger: logger
            )
            let session = await Self.fetchOracleSession(on: newConn, logger: logger)
            isConnected = .connected
            connectionHealth = .ok
            mainConnection.mainSession = session
            resultsController?.clearError()
            startPingTimer()
        } catch {
            let appError = AppDBError.from(error)
            log.error("connection failure: \(appError.description, privacy: .public)")
            await resultsController?.displayError(appError)
            isConnected = .disconnected
        }
    }

    func disconnect() {
        isConnected = .disconnected
        connectionHealth = .notConnected
        self.resultsController?.results["current"]?.clearError()
        mainConnection.mainSession = nil
        pingTask?.cancel()
        pingTask = nil
        let capturedConn = conn
        self.conn = nil
        Task {
            guard let capturedConn else { return }
            try? await capturedConn.close()
            log.debug("disconnected")
        }
    }

    static func fetchOracleSession(on conn: OracleConnection, logger: Logging.Logger) async -> OracleSession {
        let sql: OracleStatement = """
            select sid, serial#, to_number(sys_context('userenv','instance')) instance, systimestamp as ts
            from v$session where sid = sys_context('userenv','sid')
            """
        do {
            let rows = try await conn.execute(sql, logger: logger)
            for try await (sid, serial, instance, ts) in rows.decode((Int, Int, Int, Date).self) {
                return OracleSession(sid: sid, serial: serial, instance: instance, dbTimeZone: TimeZone.current)
                // Note: oracle-nio converts timestamp to UTC Date; DB tz is not directly exposed.
                _ = ts
            }
        } catch {
            log.error("getOracleSession failed: \(error.localizedDescription, privacy: .public)")
        }
        return .preview()
    }

    private func startPingTimer() {
        pingTask?.cancel()
        let connRef = conn
        let logger = oracleLogger
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { return }
                if self.resultsController?.isExecuting == true { continue }
                guard let connRef, self.isConnected == .connected else {
                    if self.connectionHealth != .notConnected {
                        self.connectionHealth = .notConnected
                    }
                    return
                }
                do {
                    try await connRef.ping()
                    if self.connectionHealth != .ok { self.connectionHealth = .ok }
                } catch {
                    log.error("ping failed: \(error.localizedDescription, privacy: .public)")
                    if self.connectionHealth == .ok { self.connectionHealth = .lost }
                }
                _ = logger
            }
        }
    }

    private nonisolated func loadTnsAliases() -> [TnsEntry] {
        let defaultPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.oracle/tnsnames.ora"
        let path = UserDefaults.standard.string(forKey: "tnsnamesPath") ?? defaultPath
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }
        return TnsParser.parse(contents)
    }

    /// Here we determine the SQL under the current cursor position
    func getCurrentSql(for editorSelectionRange: Range<String.Index>) -> String? {
        let regexOptions: NSRegularExpression.Options = [.anchorsMatchLines]
        var ret: String = ""
        if editorSelectionRange.lowerBound != editorSelectionRange.upperBound {
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

            if let range = rangeBefore {
                firstIndex = Range(range.range, in: model.text)!.upperBound
            }

            if let range = rangeAfter {
                lastIndex = Range(range.range, in: model.text)!.lowerBound
            } else {
                let semicolonToTheRightIndex = model.text.firstIndex(of: ";", after: currentIndex) ?? firstIndex
                if semicolonToTheRightIndex > firstIndex {
                    lastIndex = semicolonToTheRightIndex
                }
            }

            var sqlCandidate = String(model.text[firstIndex ..< lastIndex])
            var sqlCandidateLines = sqlCandidate.split(separator: "\n").compactMap { String($0) }
            var toRemove = IndexSet()
            for (index, l) in sqlCandidateLines.enumerated() {
                if l.starts(with: "--") { toRemove.insert(index) }
                if l.replacing(" ", with: "") == "/" { toRemove.insert(index) }
            }
            sqlCandidateLines.remove(atOffsets: toRemove)
            if sqlCandidateLines.count == 1 && sqlCandidateLines[0].starts(with: "exec ") {
                sqlCandidateLines[0] = sqlCandidateLines[0].replacing("exec ", with: "call ")
            }
            sqlCandidate = sqlCandidateLines.joined(separator: "\n")
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
        guard let conn, self.isConnected == .connected else {
            log.error("connection doesn't exist")
            isConnected = .disconnected
            resultsController?.isExecuting = false
            return
        }
        // oracle-nio does not expose a mid-flight `BREAK`; closing and reopening is the closest equivalent.
        // For now we just cancel the current view-model task (done in ResultsController.cancel()).
        resultsController?.cancelCurrent()
        resultsController?.isExecuting = false
        _ = conn
    }

    func explainPlan(for editorSelectionRange: Range<String.Index>) {
        resultsController?.isExecuting = true
        guard let conn, !conn.isClosed else {
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
        if editorSelectionRange.isEmpty { sql = model.text } else { sql = String(model.text[editorSelectionRange]) }
        let runnableSQL = RunnableSQL(sql: sql)
        guard runnableSQL.isStoredProc else { return }
        guard let conn, !conn.isClosed else {
            log.error("connection doesn't exist")
            isConnected = .disconnected
            return
        }
        resultsController?.isExecuting = true
        resultsController?.compileSource(for: runnableSQL)
        resultsController?.isExecuting = false
    }

    func newDocument(from editorSelectionRange: Range<String.Index>) -> URL? {
        var text = ""
        if editorSelectionRange.lowerBound != editorSelectionRange.upperBound {
            text = String(model.text[editorSelectionRange])
        } else {
            text = (getCurrentSql(for: editorSelectionRange) ?? "") + "\n"
        }
        var newModel = MainModel(text: text)
        newModel.connectionDetails = self.model.connectionDetails
        newModel.preferences = self.model.preferences
        if isConnected == .connected {
            newModel.autoConnect = true
        }
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let temporaryFilename = "\(UUID().uuidString).macintora"
        let temporaryFileURL = temporaryDirectoryURL.appendingPathComponent(temporaryFilename)

        do {
            let data = try JSONEncoder().encode(newModel)
            if FileManager.default.createFile(atPath: temporaryFileURL.path, contents: data, attributes: nil) {
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

    func ping() {
        guard let conn, isConnected == .connected else {
            connectionHealth = .notConnected
            return
        }
        let logger = oracleLogger
        Task { [weak self] in
            do {
                try await conn.ping()
                self?.connectionHealth = .ok
            } catch {
                log.error("ping failed: \(error.localizedDescription, privacy: .public)")
                self?.connectionHealth = .lost
            }
            _ = logger
        }
    }

    func format(of editorSelectionRange: Binding<Range<String.Index>>) {
        var text = ""
        if editorSelectionRange.wrappedValue.lowerBound != editorSelectionRange.wrappedValue.upperBound {
            text = String(model.text[editorSelectionRange.wrappedValue])
            editorSelectionRange.wrappedValue = editorSelectionRange.wrappedValue.lowerBound ..< editorSelectionRange.wrappedValue.lowerBound
        } else {
            text = getCurrentSql(for: editorSelectionRange.wrappedValue) ?? ""
            editorSelectionRange.wrappedValue = (self.model.text.firstIndex(of: text, after: model.text.startIndex) ?? model.text.startIndex) ..< (self.model.text.firstIndex(of: text, after: model.text.startIndex) ?? model.text.startIndex)
        }
        guard !text.isEmpty else { log.debug("text is empty"); return }
        let formatter = Formatter()
        Task { [self, text] in
            let formattedText = await formatter.formatSource(name: UUID().uuidString, text: text)
            self.objectWillChange.send()
            self.model.text = self.model.text.replacing(text, with: formattedText)
        }
    }
}
