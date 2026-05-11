//
//  DBBrowserRecentsTests.swift
//  MacintoraTests
//
//  Most-recently-opened list used by the ⌘K search palette: move-to-front
//  semantics, capping, and per-TNS isolation. Uses an isolated UserDefaults
//  suite so no global state leaks.
//

import XCTest
@testable import Macintora

final class DBBrowserRecentsTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "macintora.recents-tests"

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

    private func key(_ name: String, _ type: String = "TABLE", owner: String = "HR") -> DBPinnedKey {
        DBPinnedKey(owner: owner, name: name, type: type)
    }

    func test_emptyByDefault() {
        XCTAssertEqual(DBBrowserRecents.list(tns: "a", defaults: defaults), [])
    }

    func test_record_putsNewestFirst() {
        DBBrowserRecents.record(tns: "a", key("EMP"), defaults: defaults)
        DBBrowserRecents.record(tns: "a", key("DEPT"), defaults: defaults)
        XCTAssertEqual(DBBrowserRecents.list(tns: "a", defaults: defaults), [key("DEPT"), key("EMP")])
    }

    func test_record_existing_movesToFront_noDuplicate() {
        DBBrowserRecents.record(tns: "a", key("EMP"), defaults: defaults)
        DBBrowserRecents.record(tns: "a", key("DEPT"), defaults: defaults)
        DBBrowserRecents.record(tns: "a", key("EMP"), defaults: defaults)
        XCTAssertEqual(DBBrowserRecents.list(tns: "a", defaults: defaults), [key("EMP"), key("DEPT")])
    }

    func test_record_capsAtTwelve() {
        for index in 0..<20 {
            DBBrowserRecents.record(tns: "a", key("OBJ\(index)"), defaults: defaults)
        }
        let list = DBBrowserRecents.list(tns: "a", defaults: defaults)
        XCTAssertEqual(list.count, 12)
        XCTAssertEqual(list.first, key("OBJ19"))
        XCTAssertEqual(list.last, key("OBJ8"))
    }

    func test_isolation_perTNS() {
        DBBrowserRecents.record(tns: "a", key("EMP"), defaults: defaults)
        XCTAssertEqual(DBBrowserRecents.list(tns: "b", defaults: defaults), [])
    }
}
