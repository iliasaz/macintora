//
//  DBBrowserPinnedStoreTests.swift
//  MacintoraTests
//
//  Round-trips and ordering for the pinned-objects store. Uses an isolated
//  `UserDefaults(suiteName:)` instance per test so no global state leaks.
//

import XCTest
@testable import Macintora

final class DBBrowserPinnedStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "macintora.pinned-tests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func key(_ owner: String, _ name: String, _ type: String = "TABLE") -> DBPinnedKey {
        DBPinnedKey(owner: owner, name: name, type: type)
    }

    func test_emptyByDefault() {
        let store = DBBrowserPinnedStore(tns: "tns-a", defaults: defaults)
        XCTAssertEqual(store.keys, [])
    }

    func test_pin_appendsKey_andSurvivesReload() {
        let store = DBBrowserPinnedStore(tns: "tns-a", defaults: defaults)
        store.pin(key("HR", "EMP"))
        XCTAssertTrue(store.isPinned(key("HR", "EMP")))

        let reloaded = DBBrowserPinnedStore(tns: "tns-a", defaults: defaults)
        XCTAssertEqual(reloaded.keys, [key("HR", "EMP")])
    }

    func test_pin_isIdempotent_doesNotDuplicate() {
        let store = DBBrowserPinnedStore(tns: "tns-a", defaults: defaults)
        store.pin(key("HR", "EMP"))
        store.pin(key("HR", "EMP"))
        XCTAssertEqual(store.keys, [key("HR", "EMP")])
    }

    func test_unpin_removesKey() {
        let store = DBBrowserPinnedStore(tns: "tns-a", defaults: defaults)
        store.pin(key("HR", "EMP"))
        store.pin(key("HR", "DEPT"))
        store.unpin(key("HR", "EMP"))
        XCTAssertEqual(store.keys, [key("HR", "DEPT")])
    }

    func test_toggle_flipsState() {
        let store = DBBrowserPinnedStore(tns: "tns-a", defaults: defaults)
        store.toggle(key("HR", "EMP"))
        XCTAssertTrue(store.isPinned(key("HR", "EMP")))
        store.toggle(key("HR", "EMP"))
        XCTAssertFalse(store.isPinned(key("HR", "EMP")))
    }

    func test_isolation_perTNS() {
        let a = DBBrowserPinnedStore(tns: "tns-a", defaults: defaults)
        let b = DBBrowserPinnedStore(tns: "tns-b", defaults: defaults)
        a.pin(key("HR", "EMP"))
        XCTAssertFalse(b.isPinned(key("HR", "EMP")))
    }

    func test_pinnedKey_encodeRoundtrip_threeParts() {
        let k = DBPinnedKey(owner: "HR", name: "EMP", type: "TABLE")
        XCTAssertEqual(k.encoded, "HR|EMP|TABLE")
        XCTAssertEqual(DBPinnedKey(encoded: "HR|EMP|TABLE"), k)
    }

    func test_pinnedKey_decode_rejectsShortStrings() {
        XCTAssertNil(DBPinnedKey(encoded: "HR|EMP"))
        XCTAssertNil(DBPinnedKey(encoded: "HR"))
        XCTAssertNil(DBPinnedKey(encoded: ""))
    }

    func test_pinnedKey_decode_acceptsNamesContainingPipes() {
        // Names can in principle contain |; we split on the *first two* pipes
        // so the type tail can include literal pipes.
        let k = DBPinnedKey(encoded: "HR|WEIRD|NAME|TYPE_WITH|PIPE")
        XCTAssertEqual(k?.owner, "HR")
        XCTAssertEqual(k?.name, "WEIRD")
        XCTAssertEqual(k?.type, "NAME|TYPE_WITH|PIPE")
    }
}
