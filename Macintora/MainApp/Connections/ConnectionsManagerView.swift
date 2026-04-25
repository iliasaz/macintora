import SwiftUI
import AppKit
import Logging
import OracleNIO
import os

extension os.Logger {
    fileprivate static let connMgr = os.Logger(subsystem: os.Logger.subsystem, category: "connmgr")
}

/// Two-pane editor for the app-wide connection list.
///
/// All fields edit the store *live* — there is no Save/Revert dance. The
/// binding into the editor flows directly to ``ConnectionStore/upsert(_:)``,
/// which writes-through to the backing JSON file on a 100ms debounce.
/// Passwords are the one exception: they commit to the Keychain only when
/// the user moves focus out of the password field or presses Enter, so a
/// keystroke doesn't fire a `SecItemUpdate` on every character.
///
/// macOS Settings tabs render their content directly under the title bar;
/// any `.toolbar` modifier on inner views bleeds into the window's title bar
/// alongside the tab strip. So +/- and Import live in a `safeAreaInset(.bottom)`
/// strip on the sidebar, mirroring the macOS Network / Mail Accounts panes.
struct ConnectionsManagerView: View {
    @Environment(\.connectionStore) private var injectedStore
    @Environment(\.keychainService) private var keychain

    @State private var selectedID: SavedConnection.ID?
    @State private var draftDatabasePassword: String = ""
    @State private var draftWalletPassword: String = ""
    @State private var importResultMessage: String?
    @State private var deleteAllConfirmation = false
    @State private var testStatus: TestStatus = .idle

    enum TestStatus: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }

    private var store: ConnectionStore {
        guard let injectedStore else {
            preconditionFailure("ConnectionStore not installed in environment — wire it from MacOraApp.body")
        }
        return injectedStore
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 320, maxHeight: .infinity)
            detail
                .frame(minWidth: 480, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 500)
        .onAppear { selectInitialConnection() }
        .onChange(of: selectedID) { previousID, newID in
            // Commit any in-flight password edits for the previous selection
            // so they aren't lost when the user clicks away.
            if let previousID { flushPasswords(for: previousID) }
            loadPasswords(for: newID)
            testStatus = .idle
        }
        .alert(
            importResultMessage ?? "",
            isPresented: importAlertBinding
        ) {
            Button("OK") { importResultMessage = nil }
        }
        .confirmationDialog(
            "Delete all \(store.connections.count) connections?",
            isPresented: $deleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive, action: deleteAll)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes every saved connection and its Keychain passwords. The action can't be undone.")
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            ZStack {
                List(selection: $selectedID) {
                    ForEach(store.connections) { conn in
                        ConnectionRow(connection: conn)
                            .tag(conn.id)
                            .contextMenu {
                                Button("Duplicate") { duplicate(id: conn.id) }
                                Divider()
                                Button("Delete", role: .destructive) { delete(id: conn.id) }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    delete(id: conn.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)

                if store.connections.isEmpty {
                    Text("No connections yet.\nClick + to add one or use the … menu to import.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            sidebarBottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private var sidebarBottomBar: some View {
        HStack(spacing: 2) {
            Button(action: addConnection) {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
            }
            .help("Add a new connection")
            .accessibilityLabel("Add Connection")

            Button(action: deleteSelected) {
                Image(systemName: "minus")
                    .frame(width: 22, height: 22)
            }
            .disabled(selectedID == nil)
            .help("Delete the selected connection")
            .accessibilityLabel("Delete Connection")

            Menu {
                Button("Duplicate Selected") { duplicateSelected() }
                    .disabled(selectedID == nil)
                Button("Import from tnsnames.ora…") { importTnsnames() }
                Divider()
                Button("Delete All…", role: .destructive) {
                    deleteAllConfirmation = true
                }
                .disabled(store.connections.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More actions")

            Spacer()
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selectedID, store.connection(id: id) != nil {
            VStack(spacing: 0) {
                ConnectionEditorForm(
                    connection: liveBinding(for: id),
                    databasePassword: $draftDatabasePassword,
                    walletPassword: $draftWalletPassword,
                    onCommitDatabasePassword: { commitDatabasePassword(for: id) },
                    onCommitWalletPassword: { commitWalletPassword(for: id) }
                )
                Divider()
                detailFooter(connectionID: id)
            }
        } else {
            ContentUnavailableView(
                "No connection selected",
                systemImage: "server.rack",
                description: Text("Pick a connection from the list, or click + to add one.")
            )
        }
    }

    @ViewBuilder
    private func detailFooter(connectionID: SavedConnection.ID) -> some View {
        HStack(alignment: .center, spacing: 8) {
            TestStatusBadge(status: testStatus)
            Spacer()
            Button {
                Task { await runTest(for: connectionID) }
            } label: {
                if case .testing = testStatus {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Testing…")
                    }
                } else {
                    Text("Test Connection")
                }
            }
            .disabled(!canTest(connectionID: connectionID) || testStatus == .testing)
            .help("Open a connection with the values above to verify host, credentials, and wallet.")
        }
        .padding(12)
    }

    // MARK: - Live binding

    private func liveBinding(for id: SavedConnection.ID) -> Binding<SavedConnection> {
        Binding(
            get: { store.connection(id: id) ?? SavedConnection(name: "", host: "", service: .serviceName("")) },
            set: { newValue in
                store.upsert(newValue)
            }
        )
    }

    // MARK: - Sidebar actions

    private var importAlertBinding: Binding<Bool> {
        Binding(
            get: { importResultMessage != nil },
            set: { if !$0 { importResultMessage = nil } }
        )
    }

    private func selectInitialConnection() {
        if selectedID == nil {
            selectedID = store.connections.first?.id
            loadPasswords(for: selectedID)
        }
    }

    private func addConnection() {
        let new = SavedConnection(
            name: uniqueName(base: "New Connection"),
            host: "",
            port: 1521,
            service: .serviceName("")
        )
        store.upsert(new)
        selectedID = new.id
    }

    private func duplicateSelected() {
        guard let id = selectedID else { return }
        duplicate(id: id)
    }

    private func duplicate(id: SavedConnection.ID) {
        guard let source = store.connection(id: id) else { return }
        var copy = source
        copy.id = UUID()
        copy.name = uniqueName(base: "\(source.name) Copy")
        copy.createdAt = .now
        copy.updatedAt = .now
        store.upsert(copy)
        selectedID = copy.id
    }

    private func deleteSelected() {
        guard let id = selectedID else { return }
        delete(id: id)
    }

    private func delete(id: SavedConnection.ID) {
        let nextID = store.connections
            .firstIndex(where: { $0.id == id })
            .flatMap { idx -> SavedConnection.ID? in
                if idx + 1 < store.connections.count { return store.connections[idx + 1].id }
                if idx > 0 { return store.connections[idx - 1].id }
                return nil
            }
        store.delete(id: id, keychain: keychain)
        if selectedID == id { selectedID = nextID }
    }

    private func deleteAll() {
        let ids = store.connections.map(\.id)
        for id in ids {
            store.delete(id: id, keychain: keychain)
        }
        selectedID = nil
    }

    private func importTnsnames() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        if panel.runModal() == .OK, let url = panel.url {
            let count = store.importFromTnsnames(at: url.path)
            os.Logger.connMgr.notice("imported \(count, privacy: .public) entries from \(url.path, privacy: .public)")
            importResultMessage = "Imported \(count) \(count == 1 ? "connection" : "connections") from \(url.lastPathComponent)."
            if selectedID == nil, let first = store.connections.first {
                selectedID = first.id
            }
        }
    }

    // MARK: - Password handling

    private func loadPasswords(for id: SavedConnection.ID?) {
        guard let id else {
            draftDatabasePassword = ""
            draftWalletPassword = ""
            return
        }
        draftDatabasePassword = (try? keychain.password(for: id, kind: .databasePassword)) ?? ""
        draftWalletPassword = (try? keychain.password(for: id, kind: .walletPassword)) ?? ""
    }

    private func commitDatabasePassword(for id: SavedConnection.ID) {
        guard let conn = store.connection(id: id) else { return }
        if conn.savePasswordInKeychain {
            try? keychain.setPassword(draftDatabasePassword, for: id, kind: .databasePassword)
        } else {
            try? keychain.deletePassword(for: id, kind: .databasePassword)
        }
    }

    private func commitWalletPassword(for id: SavedConnection.ID) {
        guard let conn = store.connection(id: id) else { return }
        if case .wallet = conn.tls {
            try? keychain.setPassword(draftWalletPassword, for: id, kind: .walletPassword)
        } else {
            try? keychain.deletePassword(for: id, kind: .walletPassword)
        }
    }

    /// Called when the user picks a different row. Force-write any pending
    /// password edits on the connection we're leaving.
    private func flushPasswords(for id: SavedConnection.ID) {
        commitDatabasePassword(for: id)
        commitWalletPassword(for: id)
    }

    private func uniqueName(base: String) -> String {
        var candidate = base
        var n = 1
        let existing = Set(store.connections.map { $0.name.lowercased() })
        while existing.contains(candidate.lowercased()) {
            n += 1
            candidate = "\(base) \(n)"
        }
        return candidate
    }

    // MARK: - Test

    private func canTest(connectionID: SavedConnection.ID) -> Bool {
        guard let conn = store.connection(id: connectionID) else { return false }
        return !conn.host.trimmingCharacters(in: .whitespaces).isEmpty
            && !conn.service.rawValue.trimmingCharacters(in: .whitespaces).isEmpty
            && !conn.defaultUsername.trimmingCharacters(in: .whitespaces).isEmpty
            && !draftDatabasePassword.isEmpty
    }

    @MainActor
    private func runTest(for id: SavedConnection.ID) async {
        guard let conn = store.connection(id: id) else { return }
        // Make sure the password just typed is what we test, not the stale
        // Keychain value — the user might still be inside the password field
        // when they hit Test.
        commitDatabasePassword(for: id)
        commitWalletPassword(for: id)

        // Surface the most common wallet misconfiguration before we even
        // hit NIOSSL — an empty wallet password produces a generic OpenSSL
        // error that doesn't make the cause obvious.
        if case .wallet(let folderPath) = conn.tls {
            if draftWalletPassword.isEmpty {
                testStatus = .failure("Wallet password is empty. Enter it in the Wallet Password field and press Test again.")
                return
            }
            if !FileManager.default.fileExists(atPath: folderPath) {
                testStatus = .failure("Wallet folder '\(folderPath)' does not exist.")
                return
            }
            let pemPath = folderPath.hasSuffix("/") ? folderPath + "ewallet.pem" : folderPath + "/ewallet.pem"
            if !FileManager.default.fileExists(atPath: pemPath) {
                testStatus = .failure("ewallet.pem not found in '\(folderPath)'.")
                return
            }
        }

        testStatus = .testing
        let username = conn.defaultUsername
        let password = draftDatabasePassword
        let walletPassword: String? = {
            if case .wallet = conn.tls { return draftWalletPassword }
            return nil
        }()
        let role = conn.defaultRole
        let snapshot = conn

        let result: TestStatus = await Task.detached { @concurrent in
            await Self.attemptConnect(
                snapshot: snapshot,
                username: username,
                password: password,
                walletPassword: walletPassword,
                sysDBA: role == .sysDBA
            )
        }.value
        // The user might have moved on while we were connecting.
        if selectedID == id {
            testStatus = result
        }
    }

    @concurrent
    private nonisolated static func attemptConnect(
        snapshot: SavedConnection,
        username: String,
        password: String,
        walletPassword: String?,
        sysDBA: Bool
    ) async -> TestStatus {
        // Build the configuration up front so a synchronous error (bad
        // wallet path, malformed config) is reported immediately and
        // doesn't get masked by the timeout below.
        let config: OracleConnection.Configuration
        do {
            var built = try OracleEndpoint.makeConfiguration(
                saved: snapshot,
                username: username,
                password: password,
                walletPassword: walletPassword,
                sysDBA: sysDBA
            )
            built.options.connectTimeout = .seconds(10)
            config = built
        } catch {
            return .failure(error.localizedDescription)
        }

        // Capture oracle-nio's log output during the test so we can surface
        // *what* stalled, not just "20 seconds elapsed". Lines are appended
        // by a custom LogHandler shared between the test and the timeout
        // task; the UI shows them in the failure message.
        let captured = TestLogCollector()
        var logger = Logging.Logger(label: "com.iliasazonov.macintora.test") { _ in
            TestLogHandler(collector: captured)
        }
        logger.logLevel = .debug
        let testLogger = logger

        return await withTaskGroup(of: TestStatus?.self) { group in
            group.addTask {
                do {
                    let conn = try await OracleConnection.connect(
                        on: OracleEventLoopGroup.shared.next(),
                        configuration: config,
                        id: Int.random(in: 1...Int.max),
                        logger: testLogger
                    )
                    try? await conn.close()
                    return .success
                } catch is CancellationError {
                    return nil
                } catch {
                    // Map through AppDBError so we surface ORA-NNNNN codes
                    // and the server's actual message instead of the generic
                    // `OracleSQLError(code: server)` describer.
                    let app = AppDBError.from(error)
                    let trace = await captured.tail(lines: 6)
                    let body = trace.isEmpty
                        ? app.description
                        : "\(app.description)\n\nLast log lines:\n\(trace)"
                    return .failure(body)
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(20))
                if Task.isCancelled { return nil }
                let trace = await captured.tail(lines: 6)
                let hint = "If the password is in the expiry warning window, Oracle Cloud may not respond to mTLS auth — try changing it in SQL Developer first."
                let body = trace.isEmpty
                    ? "Connection timed out after 20 seconds.\n\n\(hint)"
                    : "Connection timed out after 20 seconds.\n\(hint)\n\nLast log lines (the connect was probably stuck here):\n\(trace)"
                return .failure(body)
            }
            for await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            return .failure("Test ended without a result.")
        }
    }
}

/// In-memory log sink that captures messages emitted during a Test run so
/// the UI can show the last few lines alongside a timeout / failure
/// message. Actor-isolated so concurrent log calls from oracle-nio's
/// internal tasks don't race.
private actor TestLogCollector {
    private var lines: [String] = []
    private let max: Int = 200

    func append(_ line: String) {
        lines.append(line)
        if lines.count > max { lines.removeFirst(lines.count - max) }
    }

    func tail(lines count: Int) -> String {
        lines.suffix(count).joined(separator: "\n")
    }
}

private struct TestLogHandler: Logging.LogHandler {
    let collector: TestLogCollector
    var metadata: Logging.Logger.Metadata = [:]
    var logLevel: Logging.Logger.Level = .debug

    subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: Logging.LogEvent) {
        let text = "[\(event.level)] \(event.message.description)"
        let collector = self.collector
        Task { await collector.append(text) }
    }

    func log(
        level: Logging.Logger.Level,
        message: Logging.Logger.Message,
        metadata: Logging.Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let text = "[\(level)] \(message.description)"
        let collector = self.collector
        Task { await collector.append(text) }
    }
}

private struct ConnectionRow: View {
    let connection: SavedConnection

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(connection.name).bold()
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let svc = connection.service.rawValue.isEmpty ? "—" : connection.service.rawValue
        let host = connection.host.isEmpty ? "—" : connection.host
        return "\(host):\(connection.port)/\(svc)"
    }
}

private struct TestStatusBadge: View {
    let status: ConnectionsManagerView.TestStatus

    var body: some View {
        switch status {
        case .idle, .testing:
            EmptyView()
        case .success:
            Label("Connection successful", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case .failure(let message):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .help(message)
        }
    }
}
