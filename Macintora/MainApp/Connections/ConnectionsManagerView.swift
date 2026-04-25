import SwiftUI
import AppKit
import os

extension Logger {
    fileprivate static let connMgr = Logger(subsystem: Logger.subsystem, category: "connmgr")
}

/// Two-pane editor for the app-wide connection list. Sidebar lists all
/// connections, detail shows the selected connection's form. Add / delete /
/// duplicate / import actions live in the sidebar toolbar.
///
/// Edits operate on a working copy so the user can revert. Save commits the
/// working copy (and any password fields) to the store + Keychain.
struct ConnectionsManagerView: View {
    @Environment(\.connectionStore) private var injectedStore
    @Environment(\.keychainService) private var keychain

    private var store: ConnectionStore {
        guard let injectedStore else {
            preconditionFailure("ConnectionStore not installed in environment — wire it from MacOraApp.body")
        }
        return injectedStore
    }

    @State private var selectedID: SavedConnection.ID?
    @State private var draft: SavedConnection?
    @State private var draftDatabasePassword: String = ""
    @State private var draftWalletPassword: String = ""
    @State private var hasUnsavedChanges: Bool = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            detail
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear { selectInitialConnection() }
        .onChange(of: selectedID) { _, newID in loadDraft(for: newID) }
        .onChange(of: draft) { _, _ in hasUnsavedChanges = draft != nil && draftDiffers() }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selectedID) {
            ForEach(store.connections) { conn in
                ConnectionRow(connection: conn).tag(conn.id)
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItemGroup {
                Button("Add", systemImage: "plus", action: addConnection)
                    .help("Add a new connection")
                Button("Duplicate", systemImage: "plus.square.on.square") {
                    duplicateSelected()
                }
                .disabled(selectedID == nil)
                .help("Duplicate the selected connection")
                Button("Delete", systemImage: "minus", action: deleteSelected)
                    .disabled(selectedID == nil)
                    .help("Delete the selected connection")
                Button("Import…", systemImage: "square.and.arrow.down") {
                    importTnsnames()
                }
                .help("Import entries from a tnsnames.ora file")
            }
        }
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
                .padding()
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
        guard let id = selectedID, let source = store.connection(id: id) else { return }
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
        let nextID = store.connections
            .firstIndex(where: { $0.id == id })
            .flatMap { idx -> SavedConnection.ID? in
                if idx + 1 < store.connections.count { return store.connections[idx + 1].id }
                if idx > 0 { return store.connections[idx - 1].id }
                return nil
            }
        store.delete(id: id, keychain: keychain)
        selectedID = nextID
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
            if let first = store.connections.first {
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

        // Refresh the draft so timestamps and any normalisation are visible.
        if let stored = store.connection(id: draftCopy.id) {
            draft = stored
        }
        hasUnsavedChanges = false
    }

    private func draftDiffers() -> Bool {
        guard let draft, let stored = store.connection(id: draft.id) else { return true }
        // updatedAt is bumped on save; ignore it here.
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
    }

    private var subtitle: String {
        let svc = connection.service.rawValue.isEmpty ? "—" : connection.service.rawValue
        let host = connection.host.isEmpty ? "—" : connection.host
        return "\(host):\(connection.port)/\(svc)"
    }
}
