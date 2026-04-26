import Foundation

/// A user-defined database connection persisted in the app's connection store.
///
/// Replaces the previous "look up an alias in tnsnames.ora at connect time" model.
/// Documents reference a `SavedConnection` by stable ``id``; the store
/// (``ConnectionStore``) is the source of truth for host/port/service/TLS.
nonisolated struct SavedConnection: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var service: ServiceIdentifier
    var defaultUsername: String
    var defaultRole: ConnectionRole
    var tls: TLSSettings
    var savePasswordInKeychain: Bool
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 1521,
        service: ServiceIdentifier,
        defaultUsername: String = "",
        defaultRole: ConnectionRole = .regular,
        tls: TLSSettings = .disabled,
        savePasswordInKeychain: Bool = false,
        notes: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.service = service
        self.defaultUsername = defaultUsername
        self.defaultRole = defaultRole
        self.tls = tls
        self.savePasswordInKeychain = savePasswordInKeychain
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension SavedConnection {
    /// Build from a parsed tnsnames.ora entry. The alias becomes the connection name.
    init(from entry: TnsEntry) {
        let svc: ServiceIdentifier =
            if let s = entry.serviceName { .serviceName(s) }
            else if let s = entry.sid { .sid(s) }
            else { .serviceName(entry.alias) }
        self.init(name: entry.alias, host: entry.host, port: entry.port, service: svc)
    }

    static func preview() -> SavedConnection {
        SavedConnection(name: "preview", host: "localhost", port: 1521, service: .serviceName("preview"))
    }
}

/// Service designator: an Oracle connection is identified either by service name
/// (`SERVICE_NAME=`) or by SID (`SID=`). Service name takes precedence in
/// modern deployments; SID is retained for legacy databases.
nonisolated enum ServiceIdentifier: Codable, Hashable, Sendable {
    case serviceName(String)
    case sid(String)

    var rawValue: String {
        switch self {
        case .serviceName(let s), .sid(let s): s
        }
    }

    var isServiceName: Bool {
        if case .serviceName = self { return true }
        return false
    }
}

/// TLS / wallet configuration for a connection.
///
/// - `disabled`: plain TCP. Default for on-prem databases.
/// - `system`: TLS using the system trust store; no client cert.
/// - `wallet(folderPath:)`: mTLS using an Oracle wallet folder. The wallet
///   password is stored in the Keychain alongside the connection.
nonisolated enum TLSSettings: Codable, Hashable, Sendable {
    case disabled
    case system
    case wallet(folderPath: String)
}
