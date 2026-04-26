import Foundation
import Security
import os

extension Logger {
    fileprivate static let keychain = Logger(subsystem: Logger.subsystem, category: "keychain")
}

/// Wraps `SecItem*` for the credentials stored alongside a ``SavedConnection``.
///
/// Each saved connection can hold up to two passwords — one for the database
/// login (used when "Save password in Keychain" is on) and one for the wallet
/// (when ``TLSSettings/wallet(folderPath:)`` is selected). Both are stored as
/// `kSecClassGenericPassword` items keyed by `service = bundleID`,
/// `account = "<connID>:<kind>"`.
nonisolated struct KeychainService: Sendable {
    enum SecretKind: String, Sendable {
        case databasePassword = "db"
        case walletPassword = "wallet"
    }

    enum KeychainError: Error, LocalizedError {
        case unexpectedStatus(OSStatus)
        case unexpectedItemFormat

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let s): "Keychain operation failed with status \(s)"
            case .unexpectedItemFormat: "Keychain item had an unexpected format"
            }
        }
    }

    let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "com.iliasazonov.macintora") {
        self.service = service
    }

    /// Store or replace the password for `(connectionID, kind)`. Empty string
    /// deletes the item — callers that turn off "Save password" can pass `""`
    /// to evict the secret in one call.
    func setPassword(
        _ password: String,
        for connectionID: UUID,
        kind: SecretKind
    ) throws {
        guard !password.isEmpty else {
            try deletePassword(for: connectionID, kind: kind)
            return
        }
        let account = accountKey(for: connectionID, kind: kind)
        let data = Data(password.utf8)

        var query = baseQuery(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        var status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(
                baseQuery(account: account) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
        }
        if status != errSecSuccess {
            Logger.keychain.error("setPassword failed: \(status, privacy: .public) for \(account, privacy: .public)")
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Read the password for `(connectionID, kind)`. Returns `nil` if no item
    /// is stored. Throws on unexpected Keychain errors.
    func password(for connectionID: UUID, kind: SecretKind) throws -> String? {
        let account = accountKey(for: connectionID, kind: kind)
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let str = String(data: data, encoding: .utf8) else {
                throw KeychainError.unexpectedItemFormat
            }
            return str
        case errSecItemNotFound:
            return nil
        default:
            Logger.keychain.error("password lookup failed: \(status, privacy: .public)")
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Remove the stored password for `(connectionID, kind)`. No-op if absent.
    func deletePassword(for connectionID: UUID, kind: SecretKind) throws {
        let account = accountKey(for: connectionID, kind: kind)
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Logger.keychain.error("deletePassword failed: \(status, privacy: .public)")
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Remove every secret associated with the connection. Called from
    /// ``ConnectionStore/delete(id:)``.
    func deleteAll(for connectionID: UUID) {
        for kind in [SecretKind.databasePassword, .walletPassword] {
            try? deletePassword(for: connectionID, kind: kind)
        }
    }

    private func accountKey(for connectionID: UUID, kind: SecretKind) -> String {
        "\(connectionID.uuidString):\(kind.rawValue)"
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
