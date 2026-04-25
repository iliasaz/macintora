import XCTest
@testable import Macintora

@MainActor
final class ConnectionStoreTests: XCTestCase {

    private var tempDir: URL!
    private var storeURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "macintora-conn-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storeURL = tempDir.appending(path: "connections.json", directoryHint: .notDirectory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    func test_freshStoreIsEmpty() {
        let store = ConnectionStore(storeURL: storeURL)
        XCTAssertEqual(store.connections.count, 0)
    }

    func test_upsertInsertsAndPersists() throws {
        let store = ConnectionStore(storeURL: storeURL)
        let conn = SavedConnection(name: "PROD", host: "h", service: .serviceName("prod"))
        store.upsert(conn)
        store.flush()

        XCTAssertEqual(store.connections.count, 1)
        XCTAssertEqual(store.connections[0].name, "PROD")

        let reopened = ConnectionStore(storeURL: storeURL)
        XCTAssertEqual(reopened.connections.count, 1)
        XCTAssertEqual(reopened.connections[0].id, conn.id)
        XCTAssertEqual(reopened.connections[0].host, "h")
    }

    func test_upsertReplacesExisting() {
        let store = ConnectionStore(storeURL: storeURL)
        var conn = SavedConnection(name: "STAGE", host: "old", service: .serviceName("s"))
        store.upsert(conn)
        conn.host = "new"
        store.upsert(conn)
        XCTAssertEqual(store.connections.count, 1)
        XCTAssertEqual(store.connections[0].host, "new")
    }

    func test_lookupByIDAndName() {
        let store = ConnectionStore(storeURL: storeURL)
        let conn = SavedConnection(name: "PROD", host: "h", service: .serviceName("prod"))
        store.upsert(conn)
        XCTAssertEqual(store.connection(id: conn.id)?.name, "PROD")
        XCTAssertEqual(store.connection(named: "prod")?.id, conn.id)
        XCTAssertEqual(store.connection(named: "PROD")?.id, conn.id)
        XCTAssertNil(store.connection(named: "missing"))
    }

    func test_deleteRemovesFromList() {
        let store = ConnectionStore(storeURL: storeURL)
        let conn = SavedConnection(name: "PROD", host: "h", service: .serviceName("p"))
        store.upsert(conn)
        // Use a no-op keychain — pointing it at a tests-only service so
        // delete-all is harmless even if items don't exist.
        let keychain = KeychainService(service: "com.iliasazonov.macintora.tests.\(UUID().uuidString)")
        store.delete(id: conn.id, keychain: keychain)
        XCTAssertTrue(store.connections.isEmpty)
    }

    func test_importEntriesUpsertsByName() {
        let store = ConnectionStore(storeURL: storeURL)
        // First import populates.
        let count1 = store.importTnsEntries([
            TnsEntry(alias: "PROD", host: "h1", port: 1521, serviceName: "prod"),
            TnsEntry(alias: "STAGE", host: "h2", port: 1521, serviceName: "stg")
        ])
        XCTAssertEqual(count1, 2)
        XCTAssertEqual(store.connections.count, 2)

        // Second import re-uses existing IDs and updates host.
        let prodIDBefore = store.connection(named: "PROD")?.id
        store.importTnsEntries([
            TnsEntry(alias: "PROD", host: "h1-updated", port: 1521, serviceName: "prod")
        ])
        XCTAssertEqual(store.connections.count, 2)
        XCTAssertEqual(store.connection(named: "PROD")?.host, "h1-updated")
        XCTAssertEqual(store.connection(named: "PROD")?.id, prodIDBefore)
    }

    func test_importFromTnsnamesReadsFile() throws {
        let store = ConnectionStore(storeURL: storeURL)
        let tns = """
            ORCL =
              (DESCRIPTION =
                (ADDRESS = (PROTOCOL = TCP)(HOST = h)(PORT = 1521))
                (CONNECT_DATA = (SERVICE_NAME = orcl))
              )
            """
        let path = tempDir.appending(path: "tnsnames.ora").path
        try tns.write(toFile: path, atomically: true, encoding: .utf8)

        let count = store.importFromTnsnames(at: path)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(store.connection(named: "ORCL")?.host, "h")
    }

    func test_connectionsSortedByName() {
        let store = ConnectionStore(storeURL: storeURL)
        store.upsert(SavedConnection(name: "Zebra", host: "h", service: .serviceName("z")))
        store.upsert(SavedConnection(name: "Apple", host: "h", service: .serviceName("a")))
        store.upsert(SavedConnection(name: "Mango", host: "h", service: .serviceName("m")))
        XCTAssertEqual(store.connections.map(\.name), ["Apple", "Mango", "Zebra"])
    }
}
