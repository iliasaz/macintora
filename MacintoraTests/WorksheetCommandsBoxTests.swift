//
//  WorksheetCommandsBoxTests.swift
//  MacintoraTests
//
//  Verifies the bridge box that lets the Database CommandMenu reach the
//  focused worksheet without holding a direct VM reference. The contract
//  is small: each trigger is an optional closure; setting it then calling
//  it must invoke the closure once; reassigning replaces the previous
//  closure exactly as `bind...Box` does on document re-mount.
//

import XCTest
@testable import Macintora

@MainActor
final class WorksheetCommandsBoxTests: XCTestCase {

    func test_freshBox_allTriggersAreNil() {
        let box = WorksheetCommandsBox()
        XCTAssertNil(box.runCurrent)
        XCTAssertNil(box.stop)
        XCTAssertNil(box.runScript)
        XCTAssertNil(box.runFromCursorOrSelection)
        XCTAssertNil(box.explainPlan)
        XCTAssertNil(box.compile)
        XCTAssertNil(box.format)
    }

    func test_eachTrigger_invokesClosure() {
        let box = WorksheetCommandsBox()
        var calls: [String] = []
        box.runCurrent = { calls.append("runCurrent") }
        box.stop = { calls.append("stop") }
        box.runScript = { calls.append("runScript") }
        box.runFromCursorOrSelection = { calls.append("runFromCursorOrSelection") }
        box.explainPlan = { calls.append("explainPlan") }
        box.compile = { calls.append("compile") }
        box.format = { calls.append("format") }

        box.runCurrent?()
        box.stop?()
        box.runScript?()
        box.runFromCursorOrSelection?()
        box.explainPlan?()
        box.compile?()
        box.format?()

        XCTAssertEqual(calls, [
            "runCurrent",
            "stop",
            "runScript",
            "runFromCursorOrSelection",
            "explainPlan",
            "compile",
            "format",
        ])
    }

    func test_overwriteTrigger_replacesPreviousClosure() {
        // Mirrors what document re-mount does: the previous closure must be
        // dropped so a stale, dismantled VM isn't called into.
        let box = WorksheetCommandsBox()
        var firstCalls = 0
        var secondCalls = 0
        box.runCurrent = { firstCalls += 1 }
        box.runCurrent = { secondCalls += 1 }
        box.runCurrent?()
        XCTAssertEqual(firstCalls, 0)
        XCTAssertEqual(secondCalls, 1)
    }

    func test_clearTrigger_disablesInvocation() {
        let box = WorksheetCommandsBox()
        var calls = 0
        box.runCurrent = { calls += 1 }
        box.runCurrent = nil
        box.runCurrent?()
        XCTAssertEqual(calls, 0)
    }
}
