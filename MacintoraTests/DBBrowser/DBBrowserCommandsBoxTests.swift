//
//  DBBrowserCommandsBoxTests.swift
//  MacintoraTests
//
//  Mirrors `WorksheetCommandsBoxTests` for the DB Browser bridge box that
//  lets the "DB Browser" `CommandMenu` reach the focused browser window
//  (issue #25, Item 3). The contract is the same: each trigger is an
//  optional closure; setting it then calling it invokes the closure once;
//  reassigning replaces the previous closure (document re-mount); clearing
//  disables invocation.
//

import XCTest
@testable import Macintora

@MainActor
final class DBBrowserCommandsBoxTests: XCTestCase {

    func test_freshBox_allTriggersAreNil() {
        let box = DBBrowserCommandsBox()
        XCTAssertNil(box.incrementalRefresh)
        XCTAssertNil(box.fullRefresh)
        XCTAssertNil(box.fullRefreshAndCompact)
        XCTAssertNil(box.compactOnly)
        XCTAssertNil(box.clear)
        XCTAssertNil(box.showCounts)
        XCTAssertNil(box.focusSearch)
        XCTAssertNil(box.clearSearch)
        XCTAssertNil(box.selectMainTab)
        XCTAssertNil(box.selectDetailsTab)
        XCTAssertNil(box.editSource)
        XCTAssertNil(box.refreshObject)
    }

    func test_eachTrigger_invokesClosure() {
        let box = DBBrowserCommandsBox()
        var calls: [String] = []
        box.incrementalRefresh = { calls.append("incrementalRefresh") }
        box.fullRefresh = { calls.append("fullRefresh") }
        box.fullRefreshAndCompact = { calls.append("fullRefreshAndCompact") }
        box.compactOnly = { calls.append("compactOnly") }
        box.clear = { calls.append("clear") }
        box.showCounts = { calls.append("showCounts") }
        box.focusSearch = { calls.append("focusSearch") }
        box.clearSearch = { calls.append("clearSearch") }
        box.selectMainTab = { calls.append("selectMainTab") }
        box.selectDetailsTab = { calls.append("selectDetailsTab") }
        box.editSource = { calls.append("editSource") }
        box.refreshObject = { calls.append("refreshObject") }

        box.incrementalRefresh?()
        box.fullRefresh?()
        box.fullRefreshAndCompact?()
        box.compactOnly?()
        box.clear?()
        box.showCounts?()
        box.focusSearch?()
        box.clearSearch?()
        box.selectMainTab?()
        box.selectDetailsTab?()
        box.editSource?()
        box.refreshObject?()

        XCTAssertEqual(calls, [
            "incrementalRefresh",
            "fullRefresh",
            "fullRefreshAndCompact",
            "compactOnly",
            "clear",
            "showCounts",
            "focusSearch",
            "clearSearch",
            "selectMainTab",
            "selectDetailsTab",
            "editSource",
            "refreshObject",
        ])
    }

    func test_overwriteTrigger_replacesPreviousClosure() {
        // Document re-mount must drop the previous closure so a stale,
        // dismantled VM isn't called into.
        let box = DBBrowserCommandsBox()
        var firstCalls = 0
        var secondCalls = 0
        box.incrementalRefresh = { firstCalls += 1 }
        box.incrementalRefresh = { secondCalls += 1 }
        box.incrementalRefresh?()
        XCTAssertEqual(firstCalls, 0)
        XCTAssertEqual(secondCalls, 1)
    }

    func test_clearTrigger_disablesInvocation() {
        let box = DBBrowserCommandsBox()
        var calls = 0
        box.fullRefresh = { calls += 1 }
        box.fullRefresh = nil
        box.fullRefresh?()
        XCTAssertEqual(calls, 0)
    }
}
