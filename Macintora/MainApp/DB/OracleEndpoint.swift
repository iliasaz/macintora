import Foundation
import OracleNIO
import NIOSSL

/// Resolves a document's ``ConnectionDetails`` against the app-wide
/// ``ConnectionStore`` and produces the ``OracleConnection.Configuration``
/// oracle-nio expects.
///
/// Lookup order:
/// 1. `details.savedConnectionID` is the primary key. If a ``SavedConnection``
///    with that ID exists, it provides host/port/service/TLS.
/// 2. If the ID is missing or unknown but `details.tns` is non-empty (legacy
///    documents written before the connection-manager overhaul), match the
///    name against the store. Set the ID on the document if found.
/// 3. Otherwise: ``ResolveError/unknownConnection``.
///
/// The configuration step also pulls credentials from the Keychain when
/// applicable (saved-password DB users and Oracle wallet TLS).
nonisolated enum OracleEndpoint {
    enum ResolveError: Error, LocalizedError {
        case unknownConnection
        case missingPassword
        case walletConfigurationFailed(String)

        var errorDescription: String? {
            switch self {
            case .unknownConnection:
                "No saved connection matches this document. Open Manage Connections… to fix."
            case .missingPassword:
                "Password is required."
            case .walletConfigurationFailed(let detail):
                "Wallet TLS setup failed: \(detail)"
            }
        }
    }

    /// Build the oracle-nio configuration for a document. Must be called from
    /// `@MainActor` because it touches the main-actor-isolated
    /// ``ConnectionStore``.
    @MainActor
    static func configuration(
        for details: ConnectionDetails,
        store: ConnectionStore,
        keychain: KeychainService
    ) throws -> OracleConnection.Configuration {
        guard let saved = resolve(details: details, store: store) else {
            throw ResolveError.unknownConnection
        }

        let username = details.username.isEmpty ? saved.defaultUsername : details.username
        let password: String = {
            if !details.password.isEmpty { return details.password }
            if saved.savePasswordInKeychain,
               let stored = try? keychain.password(for: saved.id, kind: .databasePassword) {
                return stored
            }
            return ""
        }()
        guard !password.isEmpty else { throw ResolveError.missingPassword }

        let walletPassword: String? = {
            guard case .wallet = saved.tls else { return nil }
            return try? keychain.password(for: saved.id, kind: .walletPassword)
        }()

        return try makeConfiguration(
            saved: saved,
            username: username,
            password: password,
            walletPassword: walletPassword,
            sysDBA: details.connectionRole == .sysDBA
        )
    }

    /// Lookup helper. Splits out so unit tests can drive the fallback path
    /// without a Keychain.
    @MainActor
    static func resolve(details: ConnectionDetails, store: ConnectionStore) -> SavedConnection? {
        if let id = details.savedConnectionID, let saved = store.connection(id: id) {
            return saved
        }
        if !details.tns.isEmpty, let saved = store.connection(named: details.tns) {
            return saved
        }
        return nil
    }

    /// Pure builder for an `OracleConnection.Configuration`. No store / Keychain
    /// dependency — easy to unit-test.
    static func makeConfiguration(
        saved: SavedConnection,
        username: String,
        password: String,
        walletPassword: String?,
        sysDBA: Bool
    ) throws -> OracleConnection.Configuration {
        let service: OracleServiceMethod
        switch saved.service {
        case .serviceName(let s): service = .serviceName(s)
        case .sid(let s): service = .sid(s)
        }

        var config = OracleConnection.Configuration(
            host: saved.host,
            port: saved.port,
            service: service,
            username: username,
            password: password
        )
        if sysDBA { config.mode = .sysDBA }

        switch saved.tls {
        case .disabled:
            break
        case .system:
            let tls = TLSConfiguration.makeClientConfiguration()
            config.tls = try .require(.init(configuration: tls))
        case .wallet(let folderPath):
            do {
                let tls = try TLSConfiguration.makeOracleWalletConfiguration(
                    wallet: folderPath,
                    walletPassword: walletPassword ?? ""
                )
                config.tls = try .require(.init(configuration: tls))
            } catch {
                throw ResolveError.walletConfigurationFailed(error.localizedDescription)
            }
        }

        return config
    }
}
