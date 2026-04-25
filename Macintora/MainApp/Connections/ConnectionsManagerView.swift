import SwiftUI
import AppKit
import os

extension Logger {
    fileprivate static let connMgr = Logger(subsystem: Logger.subsystem, category: "connmgr")
}

/// Two-pane editor for the app-wide connection list.
///
/// macOS Settings tabs render their content directly under the title bar;
/// any `.toolbar` modifier on inner views bleeds into the window's title bar
/// alongside the tab strip — which gave us a row of icons sitting next to
/// the Settings tabs. So +/- and Import live in a `safeAreaInset(.bottom)`
/// strip on the sidebar, mirroring the macOS Network / Mail Accounts panes.
struct ConnectionsManagerView: View {
    @Environment(\.connectionStore) private var injectedStore
    @Environment(\.keychainService) private var keychain

    @State private var selectedID: SavedConnection.ID?
    @State private var draft: SavedConnection?
    @State private var draftDatabasePassword: String = ""
    @State private var draftWalletPassword: String = ""
    @State private var hasUnsavedChanges: Bool = false
    @State private var importResultMessage: String?
    @State private var deleteAllConfirmation = false

    private var store: ConnectionStore {
        guard let injectedStore else {
            preconditionFailure("ConnectionStore not installed in environment — wire it from MacOraApp.body")
        }
        return injectedStore
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
            detail
                .frame(minWidth: 480)
        }
        .frame(minWidth: 760, minHeight: 500)
        .onAppear { selectInitialConnection() }
        .onChange(of: selectedID) { _, newID in loadDraft(for: newID) }
        .onChange(of: draft) { _, _ in hasUnsavedChanges = draft != nil && draftDiffers() }
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
        .listStyle(.bordered)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarBottomBar
        }
    }

    @ViewBuilder
    private var sidebarBottomBar: some View {
        HStack(spacing: 4) {
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

            Divider().frame(height: 16)

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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
    }

    @ViewBuilder
    private var detail: some View {
        if let draftConnection = Binding($draft) {
            VStack(spacing: 0) {
                ConnectionEditorForm(
                    connection: draftConnection,
                    databasePassword: $draftDatabasePassword,
                    walletPassword: $draftWalletPassword
                )
                Divider()
                HStack {
                    Spacer()
                    Button("Revert", action: revertDraft)
                        .disabled(!hasUnsavedChanges)
                    Button("Save", action: saveDraft)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSave)
                }
                .padding(12)
            }
        } else {
            ContentUnavailableView(
                "No connection selected",
                systemImage: "server.rack",
                description: Text("Pick a connection from the list, or click + to add one.")
            )
        }
    }

    // MARK: - Actions

    private var canSave: Bool {
        guard let draft else { return false }
        return !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.host.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.service.rawValue.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var importAlertBinding: Binding<Bool> {
        Binding(
            get: { importResultMessage != nil },
            set: { if !$0 { importResultMessage = nil } }
        )
    }

    private func selectInitialConnection() {
        if selectedID == nil {
            selectedID = store.connections.first?.id
        } else {
            loadDraft(for: selectedID)
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
        draft = nil
    }

    private func importTnsnames() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        if panel.runModal() == .OK, let url = panel.url {
            let count = store.importFromTnsnames(at: url.path)
            Logger.connMgr.notice("imported \(count, privacy: .public) entries from \(url.path, privacy: .public)")
            importResultMessage = "Imported \(count) \(count == 1 ? "connection" : "connections") from \(url.lastPathComponent)."
            if selectedID == nil, let first = store.connections.first {
                selectedID = first.id
            }
        }
    }

    private func loadDraft(for id: SavedConnection.ID?) {
        guard let id, let conn = store.connection(id: id) else {
            draft = nil
            draftDatabasePassword = ""
            draftWalletPassword = ""
            hasUnsavedChanges = false
            return
        }
        draft = conn
        draftDatabasePassword = (try? keychain.password(for: id, kind: .databasePassword)) ?? ""
        draftWalletPassword = (try? keychain.password(for: id, kind: .walletPassword)) ?? ""
        hasUnsavedChanges = false
    }

    private func revertDraft() {
        loadDraft(for: selectedID)
    }

    private func saveDraft() {
        guard var draftCopy = draft else { return }
        draftCopy.name = draftCopy.name.trimmingCharacters(in: .whitespaces)
        draftCopy.host = draftCopy.host.trimmingCharacters(in: .whitespaces)
        store.upsert(draftCopy)

        if draftCopy.savePasswordInKeychain {
            try? keychain.setPassword(draftDatabasePassword, for: draftCopy.id, kind: .databasePassword)
        } else {
            try? keychain.deletePassword(for: draftCopy.id, kind: .databasePassword)
        }
        if case .wallet = draftCopy.tls {
            try? keychain.setPassword(draftWalletPassword, for: draftCopy.id, kind: .walletPassword)
        } else {
            try? keychain.deletePassword(for: draftCopy.id, kind: .walletPassword)
        }

        if let stored = store.connection(id: draftCopy.id) {
            draft = stored
        }
        hasUnsavedChanges = false
    }

    private func draftDiffers() -> Bool {
        guard let draft, let stored = store.connection(id: draft.id) else { return true }
        var lhs = draft
        var rhs = stored
        lhs.updatedAt = rhs.updatedAt
        return lhs != rhs
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
