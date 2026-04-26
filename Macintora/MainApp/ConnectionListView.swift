//
//  ConnectionListView.swift
//  MacOra
//
//  Created by Ilia on 3/14/22.
//

import SwiftUI
import AppKit

/// Per-document connection picker. Reads the app-wide ``ConnectionStore`` and
/// writes the chosen connection's ID + display name back into the document's
/// ``ConnectionDetails``.
///
/// The picker is the only place that mutates `details.savedConnectionID` /
/// `details.tns` from a document; everything else (browser windows, session
/// browser, save/restore) reads them through.
struct ConnectionListView: View {
    @Environment(\.connectionStore) private var injectedStore
    @Environment(\.keychainService) private var keychain
    @Environment(\.openSettings) private var openSettings

    private var store: ConnectionStore {
        guard let injectedStore else {
            preconditionFailure("ConnectionStore not installed in environment — wire it from MacOraApp.body")
        }
        return injectedStore
    }

    @Binding var connectionStatus: ConnectionStatus
    @Binding var details: ConnectionDetails
    var connect: () -> Void
    var disconnect: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Text("Connection").font(.title)

            Picker("Connection", selection: selectionBinding) {
                Text("Select a connection…").tag(SavedConnection.ID?.none)
                ForEach(store.connections) { conn in
                    Text(conn.name).tag(SavedConnection.ID?.some(conn.id))
                }
            }
            .labelsHidden()
            .frame(minWidth: 200, alignment: .leading)
            .disabled(connectionStatus == .connected)

            Button("Manage Connections…", systemImage: "slider.horizontal.3") {
                openSettings()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(connectionStatus == .connected)

            if details.savedConnectionID == nil, !details.tns.isEmpty {
                Text("Connection '\(details.tns)' is not in your store. Use Manage Connections… to import or recreate it.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("username", text: $details.username)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 50)
                .disableAutocorrection(true)
                .disabled(connectionStatus == .connected)

            SecureField("password", text: $details.password)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 50)
                .disableAutocorrection(true)
                .disabled(connectionStatus == .connected)

            Picker("Connect As:", selection: $details.connectionRole) {
                Text("Regular").tag(ConnectionRole.regular)
                Text("SysDBA").tag(ConnectionRole.sysDBA)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
            .disabled(connectionStatus == .connected)

            Button {
                if connectionStatus == .connected {
                    disconnect()
                } else {
                    connect()
                }
            } label: {
                Text(connectionStatus == .connected ? "Disconnect" : "Connect")
            }

            Spacer()
        }
        .padding()
    }

    /// Binds the Picker to `details.savedConnectionID`. On change, updates
    /// the denormalised display fields (`tns`, default username, role).
    private var selectionBinding: Binding<SavedConnection.ID?> {
        Binding(
            get: { details.savedConnectionID },
            set: { newID in
                details.savedConnectionID = newID
                guard let newID, let conn = store.connection(id: newID) else {
                    details.tns = ""
                    return
                }
                details.tns = conn.name
                if details.username.isEmpty {
                    details.username = conn.defaultUsername
                }
                details.connectionRole = conn.defaultRole
                if details.password.isEmpty,
                   conn.savePasswordInKeychain,
                   let stored = try? keychain.password(for: conn.id, kind: .databasePassword) {
                    details.password = stored
                }
            }
        )
    }
}

#Preview {
    @Previewable @State var status: ConnectionStatus = .disconnected
    @Previewable @State var details = ConnectionDetails(username: "scott", tns: "PROD")
    return ConnectionListView(
        connectionStatus: $status,
        details: $details,
        connect: {},
        disconnect: {}
    )
}
