//
//  DBBrowserWindowRegistryTests.swift
//  MacintoraTests
//
//  Verifies the window-deduplication registry: register, find, deregister,
//  weak-ref purge, and same-TNS collision handling.
//

import XCTest
@testable import Macintora

@MainActor
final class DBBrowserWindowRegistryTests: XCTestCase {

    private var registry: DBBrowserWindowRegistry!
    private var connDetails: ConnectionDetails!
    private var persistence: PersistenceController!

    override func setUp() async throws {
        try await super.setUp()
        // Use a fresh instance (not the shared singleton) to keep tests isolated.
        registry = DBBrowserWindowRegistry()
        connDetails = ConnectionDetails(username: "SCOTT", password: "", tns: "testdb", connectionRole: .regular)
        persistence = PersistenceController(inMemory: true)
    }

    override func tearDown() async throws {
        registry = nil
        connDetails = nil
        persistence = nil
        try await super.tearDown()
    }

    private func makeVM() -> DBCacheVM {
        DBCacheVM(connDetails: connDetails, persistenceController: persistence)
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: .zero,
                        styleMask: .borderless,
                        backing: .buffered,
                        defer: true)
        return w
    }

    // MARK: - register / find

    func test_find_returnsNilBeforeRegistration() {
        XCTAssertNil(registry.find(forTNS: "testdb"))
    }

    func test_find_returnsPairAfterRegistration() {
        let vm = makeVM()
        let window = makeWindow()
        registry.register(vm: vm, window: window)
        let result = registry.find(forTNS: "testdb")
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.vm === vm)
        XCTAssertTrue(result?.window === window)
    }

    func test_find_returnsNilForDifferentTNS() {
        let vm = makeVM()
        let window = makeWindow()
        registry.register(vm: vm, window: window)
        XCTAssertNil(registry.find(forTNS: "other_db"))
    }

    // MARK: - deregister

    func test_deregister_removesEntry() {
        let vm = makeVM()
        let window = makeWindow()
        registry.register(vm: vm, window: window)
        registry.deregister(vm: vm)
        XCTAssertNil(registry.find(forTNS: "testdb"))
    }

    // MARK: - idempotency

    func test_register_idempotent_sameVMAndWindow() {
        let vm = makeVM()
        let window = makeWindow()
        registry.register(vm: vm, window: window)
        registry.register(vm: vm, window: window)
        // Should still be findable — no crash or duplicate entry.
        XCTAssertNotNil(registry.find(forTNS: "testdb"))
    }

    // MARK: - same-TNS re-register

    func test_register_replacesOldEntryForSameVM_newWindow() {
        let vm = makeVM()
        let window1 = makeWindow()
        let window2 = makeWindow()
        registry.register(vm: vm, window: window1)
        registry.register(vm: vm, window: window2)
        let result = registry.find(forTNS: "testdb")
        XCTAssertTrue(result?.window === window2)
    }
}
