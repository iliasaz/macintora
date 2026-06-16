import Foundation
import OracleNIO
import NIOSSL
import MacintoraPluginAPI

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
            // A registered WalletTLSProvider (e.g. a private plugin) gets first
            // crack; nil means "not my wallet" → fall back to the default path.
            if let material = pluginWalletMaterial(forWalletAt: URL(filePath: folderPath)) {
                do {
                    config.tls = try .require(.init(configuration: material.makeTLSConfiguration()))
                } catch {
                    throw ResolveError.walletConfigurationFailed(error.localizedDescription)
                }
            } else {
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
        }

        return config
    }

    /// First registered ``WalletTLSProvider`` that handles `folder`, if any.
    /// A provider returning nil means "not my wallet"; a thrown error means it
    /// recognised the wallet but failed — we fall back to the default path.
    static func pluginWalletMaterial(forWalletAt folder: URL) -> WalletTLSMaterial? {
        for provider in PluginRegistry.shared.plugins(WalletTLSProvider.self) {
            if let material = try? provider.walletMaterial(forWalletAt: folder) {
                return material
            }
        }
        return nil
    }

    /// Display name of the first registered ``WalletTLSProvider`` that can open
    /// the wallet at `folder` passwordlessly, or `nil` if none can. Cheap enough
    /// for UI use (delegates to each provider's `canHandle`). With no plugins
    /// registered (the open-source build) this is always `nil`, so the UI shows
    /// the normal password field.
    static func passwordlessWalletProvider(forWalletAt folder: URL) -> String? {
        PluginRegistry.shared.plugins(WalletTLSProvider.self)
            .first { $0.canHandle(walletFolderAt: folder) }?
            .displayName
    }

    /// Pre-flight validation for a wallet connection test, surfaced before NIOSSL
    /// so common misconfigurations get a clear message. Returns `nil` if the
    /// wallet looks usable, otherwise a user-facing error string.
    ///
    /// When `passwordless` is true a plugin supplies the TLS material (e.g. an
    /// auto-login wallet), so neither a wallet password nor `ewallet.pem` is
    /// required — only the folder must exist. Otherwise the default path needs a
    /// non-empty password and an `ewallet.pem`.
    static func walletTestPreflightError(
        folderPath: String,
        passwordIsEmpty: Bool,
        passwordless: Bool,
        fileManager: FileManager = .default
    ) -> String? {
        guard fileManager.fileExists(atPath: folderPath) else {
            return "Wallet folder '\(folderPath)' does not exist."
        }
        if passwordless { return nil }
        if passwordIsEmpty {
            return "Wallet password is empty. Enter it in the Wallet Password field and press Test again."
        }
        let pemPath = folderPath.hasSuffix("/") ? folderPath + "ewallet.pem" : folderPath + "/ewallet.pem"
        guard fileManager.fileExists(atPath: pemPath) else {
            return "ewallet.pem not found in '\(folderPath)'."
        }
        return nil
    }

    #if DEBUG
    /// Test hook: true if a registered plugin produces a usable TLS config for `folder`.
    static func _debugPluginProducesTLS(forWalletAt folder: URL) throws -> Bool {
        guard let material = pluginWalletMaterial(forWalletAt: folder) else { return false }
        _ = try material.makeTLSConfiguration()
        return true
    }
    #endif
}

extension WalletTLSMaterial {
    /// Build a client mutual-TLS configuration from the wallet's PKCS#12 bytes.
    func makeTLSConfiguration() throws -> TLSConfiguration {
        let bundle = try NIOSSLPKCS12Bundle(buffer: [UInt8](pkcs12DER), passphrase: passphrase)
        var tls = TLSConfiguration.makeClientConfiguration()
        tls.certificateChain = bundle.certificateChain.map { .certificate($0) }
        tls.privateKey = .privateKey(bundle.privateKey)
        return tls
    }
}
