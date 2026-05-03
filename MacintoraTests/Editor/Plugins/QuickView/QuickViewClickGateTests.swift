//
//  QuickViewClickGateTests.swift
//  MacintoraTests
//
//  Exercises `STDBObjectQuickViewPlugin.Coordinator.shouldTrigger(...)` —
//  the predicate that decides whether a process-global ⌘+leftMouseDown
//  event should pop a Quick View on a given text view. Covers the four
//  important cases:
//    * click in the text view's own window, hit-tests the text view → true
//    * click in the text view's own window, hit-tests a sibling view → false
//    * click in a different window → false
//    * text view detached (no window) → false
//
//  Synthesizing real `NSEvent` mouse events is awkward, so the predicate
//  takes the pieces the monitor reads (`eventWindow`, `locationInWindow`)
//  directly; we drive it with plain views instead. NSWindow instances are
//  released to ARC at scope exit — calling `close()` from a teardown block
//  occasionally double-frees through the autorelease pool, so we let the
//  default cleanup happen.
//

import AppKit
import XCTest
@testable import Macintora

@MainActor
final class QuickViewClickGateTests: XCTestCase {

    func test_clickInsideTextView_inSameWindow_passes() {
        let (window, textView) = makeWindowWithTextView()
        let inside = NSPoint(x: 50, y: 50)   // squarely inside textView
        XCTAssertTrue(STDBObjectQuickViewPlugin.Coordinator.shouldTrigger(
            eventWindow: window,
            locationInWindow: inside,
            textView: textView))
    }

    func test_clickOnSiblingView_inSameWindow_isRejected() {
        let (window, textView) = makeWindowWithTextView()
        // Sibling pane below the text view in the same content view.
        let sibling = NSView(frame: NSRect(x: 0, y: 200, width: 400, height: 100))
        window.contentView?.addSubview(sibling)

        let onSibling = NSPoint(x: 50, y: 250)
        XCTAssertFalse(STDBObjectQuickViewPlugin.Coordinator.shouldTrigger(
            eventWindow: window,
            locationInWindow: onSibling,
            textView: textView))
    }

    func test_clickInDifferentWindow_isRejected() {
        let (_, textView) = makeWindowWithTextView()
        let otherWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                   styleMask: [],
                                   backing: .buffered,
                                   defer: true)

        XCTAssertFalse(STDBObjectQuickViewPlugin.Coordinator.shouldTrigger(
            eventWindow: otherWindow,
            locationInWindow: NSPoint(x: 50, y: 50),
            textView: textView))
    }

    func test_textViewWithoutWindow_isRejected() {
        let detached = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertFalse(STDBObjectQuickViewPlugin.Coordinator.shouldTrigger(
            eventWindow: nil,
            locationInWindow: .zero,
            textView: detached))
    }

    func test_nilEventWindow_isRejected() {
        let (_, textView) = makeWindowWithTextView()
        XCTAssertFalse(STDBObjectQuickViewPlugin.Coordinator.shouldTrigger(
            eventWindow: nil,
            locationInWindow: NSPoint(x: 50, y: 50),
            textView: textView))
    }

    // MARK: - Helpers

    /// Builds a window with a single text-view-like NSView occupying the
    /// upper half of its content view. The text view is the only descendant
    /// the gate should accept.
    private func makeWindowWithTextView() -> (NSWindow, NSView) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [],
                              backing: .buffered,
                              defer: true)
        let textView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        window.contentView?.addSubview(textView)
        return (window, textView)
    }
}
