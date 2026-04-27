import XCTest
@testable import Macintora

/// Live-DB repro for the full-refresh crash. Skips unless the local
/// `c4-local` connection is configured with a saved Keychain password.
@MainActor
final class FullRefreshReproTests: XCTestCase {

    func testFullRefresh_c4Local() async throws {
        let store = ConnectionStore()
        guard let saved = store.connection(named: "c4-local") else {
            throw XCTSkip("c4-local not present in connections.json")
        }
        let appBundleID = "com.iliasazonov.macintora"
        let keychain = KeychainService(service: appBundleID)
        guard
            saved.savePasswordInKeychain,
            let pwd = try? keychain.password(for: saved.id, kind: .databasePassword),
            !pwd.isEmpty
        else {
            throw XCTSkip("Saved password for c4-local not available in keychain")
        }

        var details = ConnectionDetails(
            savedConnectionID: saved.id,
            username: saved.defaultUsername,
            password: pwd,
            tns: saved.name,
            connectionRole: .regular
        )
        _ = details

        let cache = DBCacheVM(connDetails: details)
        cache.store = store
        cache.keychain = keychain

        cache.updateCache(ignoreLastUpdate: true)

        // Poll until the spawned utility-priority Task flips the flag back.
        let deadline = Date().addingTimeInterval(900)
        while cache.isReloading, Date() < deadline {
            try await Task.sleep(for: .milliseconds(500))
        }

        XCTAssertFalse(cache.isReloading, "Full refresh did not complete within 15 minutes")
    }
}
