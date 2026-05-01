import XCTest
@testable import Macintora

@MainActor
final class OracleEndpointTests: XCTestCase {

    private var tempDir: URL!
    private var store: ConnectionStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "macintora-endpoint-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = ConnectionStore(storeURL: tempDir.appending(path: "connections.json", directoryHint: .notDirectory))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private func uniqueKeychain() -> KeychainService {
        KeychainService(service: "com.iliasazonov.macintora.tests.\(UUID().uuidString)")
    }

    // MARK: - resolve()

    func test_resolveByID() {
        let conn = SavedConnection(name: "PROD", host: "h", service: .serviceName("prod"))
        store.upsert(conn)
        let details = ConnectionDetails(savedConnectionID: conn.id, tns: "PROD")
        XCTAssertEqual(OracleEndpoint.resolve(details: details, store: store)?.id, conn.id)
    }

    func test_resolveByLegacyName() {
        let conn = SavedConnection(name: "STAGE", host: "h", service: .serviceName("stg"))
        store.upsert(conn)
        let details = ConnectionDetails(savedConnectionID: nil, tns: "stage")
        XCTAssertEqual(OracleEndpoint.resolve(details: details, store: store)?.id, conn.id)
    }

    func test_resolveReturnsNilWhenNothingMatches() {
        let details = ConnectionDetails(savedConnectionID: UUID(), tns: "missing")
        XCTAssertNil(OracleEndpoint.resolve(details: details, store: store))
    }

    // MARK: - configuration()

    func test_configurationFromStoreWithProvidedPassword() throws {
        let conn = SavedConnection(name: "PROD", host: "db", port: 1521, service: .serviceName("prod"))
        store.upsert(conn)
        let details = ConnectionDetails(
            savedConnectionID: conn.id, username: "scott", password: "tiger", tns: "PROD"
        )
        let config = try OracleEndpoint.configuration(for: details, store: store, keychain: uniqueKeychain())
        XCTAssertEqual(config.host, "db")
        XCTAssertEqual(config.port, 1521)
        XCTAssertEqual(config.mode, .default)
    }

    func test_configurationFallsBackToKeychainPassword() async throws {
        let keychain = uniqueKeychain()
        var conn = SavedConnection(name: "PROD", host: "h", service: .serviceName("p"))
        conn.savePasswordInKeychain = true
        store.upsert(conn)
        // Hop off main — `SecItem*` warns when called on the main thread.
        let connID = conn.id
        try await Task.detached(priority: .userInitiated) {
            try keychain.setPassword("from-keychain", for: connID, kind: .databasePassword)
        }.value

        let details = ConnectionDetails(
            savedConnectionID: conn.id, username: "scott", password: "", tns: "PROD"
        )
        // We can't read back the password from the configuration directly, but
        // we can confirm the call doesn't throw `.missingPassword`.
        XCTAssertNoThrow(try OracleEndpoint.configuration(for: details, store: store, keychain: keychain))
        await Task.detached { keychain.deleteAll(for: connID) }.value
    }

    func test_configurationThrowsOnMissingPassword() {
        let conn = SavedConnection(name: "PROD", host: "h", service: .serviceName("p"))
        store.upsert(conn)
        let details = ConnectionDetails(savedConnectionID: conn.id, username: "u", password: "", tns: "PROD")
        XCTAssertThrowsError(try OracleEndpoint.configuration(for: details, store: store, keychain: uniqueKeychain()))
    }

    func test_configurationThrowsOnUnknownConnection() {
        let details = ConnectionDetails(savedConnectionID: UUID(), tns: "ghost")
        XCTAssertThrowsError(try OracleEndpoint.configuration(for: details, store: store, keychain: uniqueKeychain()))
    }

    func test_configurationSysDBAModeSet() throws {
        let conn = SavedConnection(name: "DB", host: "h", service: .serviceName("s"))
        store.upsert(conn)
        let details = ConnectionDetails(
            savedConnectionID: conn.id, username: "sys", password: "p", tns: "DB", connectionRole: .sysDBA
        )
        let config = try OracleEndpoint.configuration(for: details, store: store, keychain: uniqueKeychain())
        XCTAssertEqual(config.mode, .sysDBA)
    }

    // MARK: - makeConfiguration() (pure, no store/keychain)

    func test_makeConfigurationServiceName() throws {
        let conn = SavedConnection(name: "PROD", host: "h", port: 1521, service: .serviceName("svc"))
        let cfg = try OracleEndpoint.makeConfiguration(
            saved: conn, username: "u", password: "p", walletPassword: nil, sysDBA: false
        )
        XCTAssertEqual(cfg.host, "h")
        XCTAssertEqual(cfg.port, 1521)
    }

    func test_makeConfigurationSystemTLSDoesNotThrow() throws {
        let conn = SavedConnection(name: "TLS", host: "h", service: .serviceName("s"), tls: .system)
        // System TLS configuration is happy with no wallet password.
        XCTAssertNoThrow(
            try OracleEndpoint.makeConfiguration(
                saved: conn, username: "u", password: "p",
                walletPassword: nil, sysDBA: false
            )
        )
    }

    func test_makeConfigurationWalletThrowsOnBadPath() {
        let conn = SavedConnection(
            name: "ATP", host: "h", service: .serviceName("svc"),
            tls: .wallet(folderPath: "/nonexistent/wallet/path")
        )
        XCTAssertThrowsError(
            try OracleEndpoint.makeConfiguration(
                saved: conn, username: "u", password: "p",
                walletPassword: "wrong", sysDBA: false
            )
        ) { error in
            guard case OracleEndpoint.ResolveError.walletConfigurationFailed = error else {
                return XCTFail("expected walletConfigurationFailed, got \(error)")
            }
        }
    }
}
