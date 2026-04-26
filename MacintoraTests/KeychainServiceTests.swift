import XCTest
@testable import Macintora

final class KeychainServiceTests: XCTestCase {

    /// Run against a unique service prefix so we never collide with the real
    /// app keychain. The teardown wipes everything written under this prefix.
    private var keychain: KeychainService!
    private var connID: UUID!

    override func setUp() {
        super.setUp()
        keychain = KeychainService(service: "com.iliasazonov.macintora.tests.\(UUID().uuidString)")
        connID = UUID()
    }

    override func tearDown() {
        keychain.deleteAll(for: connID)
        super.tearDown()
    }

    func test_setAndReadDatabasePassword() throws {
        try keychain.setPassword("hunter2", for: connID, kind: .databasePassword)
        XCTAssertEqual(try keychain.password(for: connID, kind: .databasePassword), "hunter2")
    }

    func test_overwriteExisting() throws {
        try keychain.setPassword("first", for: connID, kind: .databasePassword)
        try keychain.setPassword("second", for: connID, kind: .databasePassword)
        XCTAssertEqual(try keychain.password(for: connID, kind: .databasePassword), "second")
    }

    func test_separateKindsAreIndependent() throws {
        try keychain.setPassword("dbpw", for: connID, kind: .databasePassword)
        try keychain.setPassword("walletpw", for: connID, kind: .walletPassword)
        XCTAssertEqual(try keychain.password(for: connID, kind: .databasePassword), "dbpw")
        XCTAssertEqual(try keychain.password(for: connID, kind: .walletPassword), "walletpw")
    }

    func test_separateConnectionIDsAreIndependent() throws {
        let other = UUID()
        defer { keychain.deleteAll(for: other) }
        try keychain.setPassword("a", for: connID, kind: .databasePassword)
        try keychain.setPassword("b", for: other, kind: .databasePassword)
        XCTAssertEqual(try keychain.password(for: connID, kind: .databasePassword), "a")
        XCTAssertEqual(try keychain.password(for: other, kind: .databasePassword), "b")
    }

    func test_readMissingReturnsNil() throws {
        XCTAssertNil(try keychain.password(for: connID, kind: .databasePassword))
    }

    func test_deleteRemovesItem() throws {
        try keychain.setPassword("temp", for: connID, kind: .databasePassword)
        try keychain.deletePassword(for: connID, kind: .databasePassword)
        XCTAssertNil(try keychain.password(for: connID, kind: .databasePassword))
    }

    func test_setEmptyDeletes() throws {
        try keychain.setPassword("temp", for: connID, kind: .databasePassword)
        try keychain.setPassword("", for: connID, kind: .databasePassword)
        XCTAssertNil(try keychain.password(for: connID, kind: .databasePassword))
    }

    func test_deleteAllRemovesBothKinds() throws {
        try keychain.setPassword("dbpw", for: connID, kind: .databasePassword)
        try keychain.setPassword("walletpw", for: connID, kind: .walletPassword)
        keychain.deleteAll(for: connID)
        XCTAssertNil(try keychain.password(for: connID, kind: .databasePassword))
        XCTAssertNil(try keychain.password(for: connID, kind: .walletPassword))
    }
}
