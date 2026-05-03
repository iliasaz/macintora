//
//  EditorQuickViewBoxTests.swift
//  MacintoraTests
//
//  Verifies the SwiftUI ↔ AppKit bridge object that lets the menu command
//  trigger Quick View on the focused editor. The contract is small but
//  critical: a nil trigger means the menu disables the Quick View item;
//  a non-nil trigger fires the editor's "trigger at cursor" closure once
//  per menu invocation.
//

import XCTest
@testable import Macintora

@MainActor
final class EditorQuickViewBoxTests: XCTestCase {

    func test_freshBox_hasNilTrigger() {
        let box = EditorQuickViewBox()
        XCTAssertNil(box.trigger,
                     "A box with no editor wired must report nil so the menu Button can disable")
    }

    func test_setTrigger_invokesClosureWhenCalled() {
        let box = EditorQuickViewBox()
        var calls = 0
        box.trigger = { calls += 1 }
        box.trigger?()
        XCTAssertEqual(calls, 1)
        box.trigger?()
        XCTAssertEqual(calls, 2,
                       "Menu invocation should fire the closure each time the user picks it")
    }

    func test_overwriteTrigger_replacesPreviousClosure() {
        // Mirrors what `Coordinator.bindQuickViewBox` does on document
        // re-mount: the previous closure must be dropped so a stale,
        // dismantled editor isn't called into.
        let box = EditorQuickViewBox()
        var firstCalls = 0
        var secondCalls = 0
        box.trigger = { firstCalls += 1 }
        box.trigger = { secondCalls += 1 }
        box.trigger?()
        XCTAssertEqual(firstCalls, 0)
        XCTAssertEqual(secondCalls, 1)
    }

    func test_clearTrigger_disablesInvocation() {
        let box = EditorQuickViewBox()
        var calls = 0
        box.trigger = { calls += 1 }
        box.trigger = nil
        box.trigger?()
        XCTAssertEqual(calls, 0)
    }
}
