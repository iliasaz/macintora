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
        let kc = keychain!
        let id = connID!
        // Avoid the macOS "should not be called on the main thread" runtime
        // warning by hopping off-main for the teardown's keychain access.
        Task.detached { kc.deleteAll(for: id) }
        super.tearDown()
    }

    /// Hop off the main actor — the underlying `SecItem*` APIs warn when
    /// invoked on the main thread.
    private func offMain<T: Sendable>(_ work: @Sendable @escaping () throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated) {
            try work()
        }.value
    }

    func test_setAndReadDatabasePassword() async throws {
        let kc = keychain!
        let id = connID!
        try await offMain { try kc.setPassword("hunter2", for: id, kind: .databasePassword) }
        let pw = try await offMain { try kc.password(for: id, kind: .databasePassword) }
        XCTAssertEqual(pw, "hunter2")
    }

    func test_overwriteExisting() async throws {
        let kc = keychain!
        let id = connID!
        try await offMain { try kc.setPassword("first", for: id, kind: .databasePassword) }
        try await offMain { try kc.setPassword("second", for: id, kind: .databasePassword) }
        let pw = try await offMain { try kc.password(for: id, kind: .databasePassword) }
        XCTAssertEqual(pw, "second")
    }

    func test_separateKindsAreIndependent() async throws {
        let kc = keychain!
        let id = connID!
        try await offMain { try kc.setPassword("dbpw", for: id, kind: .databasePassword) }
        try await offMain { try kc.setPassword("walletpw", for: id, kind: .walletPassword) }
        let dbPw = try await offMain { try kc.password(for: id, kind: .databasePassword) }
        let walletPw = try await offMain { try kc.password(for: id, kind: .walletPassword) }
        XCTAssertEqual(dbPw, "dbpw")
        XCTAssertEqual(walletPw, "walletpw")
    }

    func test_separateConnectionIDsAreIndependent() async throws {
        let kc = keychain!
        let id = connID!
        let other = UUID()
        defer { Task.detached { kc.deleteAll(for: other) } }
        try await offMain { try kc.setPassword("a", for: id, kind: .databasePassword) }
        try await offMain { try kc.setPassword("b", for: other, kind: .databasePassword) }
        let a = try await offMain { try kc.password(for: id, kind: .databasePassword) }
        let b = try await offMain { try kc.password(for: other, kind: .databasePassword) }
        XCTAssertEqual(a, "a")
        XCTAssertEqual(b, "b")
    }

    func test_readMissingReturnsNil() async throws {
        let kc = keychain!
        let id = connID!
        let pw = try await offMain { try kc.password(for: id, kind: .databasePassword) }
        XCTAssertNil(pw)
    }

    func test_deleteRemovesItem() async throws {
        let kc = keychain!
        let id = connID!
        try await offMain { try kc.setPassword("temp", for: id, kind: .databasePassword) }
        try await offMain { try kc.deletePassword(for: id, kind: .databasePassword) }
        let pw = try await offMain { try kc.password(for: id, kind: .databasePassword) }
        XCTAssertNil(pw)
    }

    func test_setEmptyDeletes() async throws {
        let kc = keychain!
        let id = connID!
        try await offMain { try kc.setPassword("temp", for: id, kind: .databasePassword) }
        try await offMain { try kc.setPassword("", for: id, kind: .databasePassword) }
        let pw = try await offMain { try kc.password(for: id, kind: .databasePassword) }
        XCTAssertNil(pw)
    }

    func test_deleteAllRemovesBothKinds() async throws {
        let kc = keychain!
        let id = connID!
        try await offMain { try kc.setPassword("dbpw", for: id, kind: .databasePassword) }
        try await offMain { try kc.setPassword("walletpw", for: id, kind: .walletPassword) }
        try await offMain { kc.deleteAll(for: id) }
        let dbPw = try await offMain { try kc.password(for: id, kind: .databasePassword) }
        let walletPw = try await offMain { try kc.password(for: id, kind: .walletPassword) }
        XCTAssertNil(dbPw)
        XCTAssertNil(walletPw)
    }
}
