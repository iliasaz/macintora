import SwiftUI
import AppKit

/// Editor pane for a single ``SavedConnection``. Bound to a working copy held
/// by the parent (`ConnectionsManagerView`) so the user can cancel without
/// disturbing the store.
///
/// The form supports three input modes for the host/port/service fields:
/// 1. Direct entry (always available).
/// 2. "Paste JDBC URL" — applies the parsed result to the structured fields.
/// 3. "Paste TNS descriptor" — same, for `(DESCRIPTION=…)` blobs.
///
/// Wallet password and (optional) database password live in the Keychain; the
/// view holds them in `@State` only while the user is editing, then writes
/// them through ``KeychainService`` on Save.
struct ConnectionEditorForm: View {
    @Binding var connection: SavedConnection
    @Binding var databasePassword: String
    @Binding var walletPassword: String

    @State private var jdbcPaste: String = ""
    @State private var descriptorPaste: String = ""
    @State private var pasteError: String?

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: $connection.name)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                TextField("Notes", text: $connection.notes, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Endpoint") {
                TextField("Host", text: $connection.host)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                TextField("Port", value: $connection.port, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                ServiceIdentifierEditor(service: $connection.service)
            }

            Section("Quick paste") {
                QuickPasteRow(
                    label: "JDBC URL",
                    placeholder: "jdbc:oracle:thin:@host:1521/svc",
                    text: $jdbcPaste,
                    onApply: applyJDBC
                )
                QuickPasteRow(
                    label: "TNS descriptor",
                    placeholder: "(DESCRIPTION=(ADDRESS=…)(CONNECT_DATA=…))",
                    text: $descriptorPaste,
                    onApply: applyDescriptor
                )
                if let pasteError {
                    Text(pasteError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Authentication") {
                TextField("Default username", text: $connection.defaultUsername)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                Picker("Connect as", selection: $connection.defaultRole) {
                    Text("Regular").tag(ConnectionRole.regular)
                    Text("SysDBA").tag(ConnectionRole.sysDBA)
                }
                .pickerStyle(.segmented)
                Toggle("Save password in Keychain", isOn: $connection.savePasswordInKeychain)
                if connection.savePasswordInKeychain {
                    SecureField("Password", text: $databasePassword)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section("TLS") {
                TLSSettingsEditor(
                    tls: $connection.tls,
                    walletPassword: $walletPassword
                )
            }
        }
        .formStyle(.grouped)
    }

    private func applyJDBC() {
        do {
            let result = try JDBCURLParser.parse(jdbcPaste)
            connection.host = result.host
            connection.port = result.port
            connection.service = result.service
            // Only upgrade TLS — never silently disable a wallet the user already
            // chose.
            switch result.tls {
            case .system:
                if case .disabled = connection.tls { connection.tls = .system }
            case .disabled, .wallet:
                break
            }
            jdbcPaste = ""
            pasteError = nil
        } catch {
            pasteError = error.localizedDescription
        }
    }

    private func applyDescriptor() {
        guard let entry = TnsParser.parseDescriptor(descriptorPaste) else {
            pasteError = "Could not parse descriptor."
            return
        }
        connection.host = entry.host
        connection.port = entry.port
        if let svc = entry.serviceName {
            connection.service = .serviceName(svc)
        } else if let sid = entry.sid {
            connection.service = .sid(sid)
        }
        descriptorPaste = ""
        pasteError = nil
    }
}

private struct QuickPasteRow: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let onApply: () -> Void

    var body: some View {
        HStack {
            TextField(label, text: $text, prompt: Text(placeholder))
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
            Button("Apply", action: onApply)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

private struct ServiceIdentifierEditor: View {
    @Binding var service: ServiceIdentifier

    private enum Kind: String, Hashable, CaseIterable {
        case serviceName, sid

        var label: String {
            switch self {
            case .serviceName: "Service Name"
            case .sid: "SID"
            }
        }
    }

    private var kindBinding: Binding<Kind> {
        Binding(
            get: { service.isServiceName ? .serviceName : .sid },
            set: { newKind in
                let raw = service.rawValue
                service = (newKind == .serviceName) ? .serviceName(raw) : .sid(raw)
            }
        )
    }

    private var rawBinding: Binding<String> {
        Binding(
            get: { service.rawValue },
            set: { service = service.isServiceName ? .serviceName($0) : .sid($0) }
        )
    }

    var body: some View {
        Picker("Service kind", selection: kindBinding) {
            ForEach(Kind.allCases, id: \.self) { kind in
                Text(kind.label).tag(kind)
            }
        }
        .pickerStyle(.segmented)

        TextField(service.isServiceName ? "Service name" : "SID", text: rawBinding)
            .textFieldStyle(.roundedBorder)
            .disableAutocorrection(true)
    }
}

private struct TLSSettingsEditor: View {
    @Binding var tls: TLSSettings
    @Binding var walletPassword: String

    private enum Mode: String, CaseIterable, Hashable {
        case disabled, system, wallet

        var label: String {
            switch self {
            case .disabled: "Disabled"
            case .system: "System TLS"
            case .wallet: "Oracle Wallet"
            }
        }
    }

    private var modeBinding: Binding<Mode> {
        Binding(
            get: {
                switch tls {
                case .disabled: .disabled
                case .system: .system
                case .wallet: .wallet
                }
            },
            set: { newMode in
                switch newMode {
                case .disabled: tls = .disabled
                case .system: tls = .system
                case .wallet:
                    if case .wallet = tls { return }
                    tls = .wallet(folderPath: "")
                }
            }
        )
    }

    private var walletPathBinding: Binding<String> {
        Binding(
            get: {
                if case let .wallet(path) = tls { return path }
                return ""
            },
            set: { tls = .wallet(folderPath: $0) }
        )
    }

    var body: some View {
        Picker("Mode", selection: modeBinding) {
            ForEach(Mode.allCases, id: \.self) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)

        if case .wallet = tls {
            HStack {
                TextField("Wallet folder", text: walletPathBinding)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                Button("Choose…", action: chooseWalletFolder)
            }
            SecureField("Wallet password", text: $walletPassword)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func chooseWalletFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Wallet Folder"
        if panel.runModal() == .OK, let url = panel.url {
            tls = .wallet(folderPath: url.path)
        }
    }
}
