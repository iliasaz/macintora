//
//  EditorToggleCommentBoxTests.swift
//  MacintoraTests
//
//  Verifies the bridge object that lets the ⌘/ menu command call into the
//  focused editor's `toggleLineComment(_:)` without the menu holding a
//  direct text-view reference.
//

import XCTest
@testable import Macintora

@MainActor
final class EditorToggleCommentBoxTests: XCTestCase {

    func test_freshBox_hasNilTrigger() {
        let box = EditorToggleCommentBox()
        XCTAssertNil(box.trigger,
                     "A box with no editor wired must report nil so the menu can disable")
    }

    func test_setTrigger_invokesClosureWhenCalled() {
        let box = EditorToggleCommentBox()
        var calls = 0
        box.trigger = { calls += 1 }
        box.trigger?()
        XCTAssertEqual(calls, 1)
        box.trigger?()
        XCTAssertEqual(calls, 2)
    }

    func test_overwriteTrigger_replacesPreviousClosure() {
        let box = EditorToggleCommentBox()
        var firstCalls = 0
        var secondCalls = 0
        box.trigger = { firstCalls += 1 }
        box.trigger = { secondCalls += 1 }
        box.trigger?()
        XCTAssertEqual(firstCalls, 0)
        XCTAssertEqual(secondCalls, 1)
    }

    func test_clearTrigger_disablesInvocation() {
        let box = EditorToggleCommentBox()
        var calls = 0
        box.trigger = { calls += 1 }
        box.trigger = nil
        box.trigger?()
        XCTAssertEqual(calls, 0)
    }
}
