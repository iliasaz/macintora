//
//  WindowLayoutPersisterTests.swift
//  MacintoraTests
//
//  Regression coverage for the launch-time crash where AppKit replays
//  persisted `NSSplitView` divider sizes that don't fit the current
//  window — typically because the user disconnected an external display
//  between sessions and the saved sizes were measured against a much
//  wider canvas. Replaying those sizes drives
//  `_NSSplitViewItemViewWrapper.updateConstraints` past AppKit's
//  "more passes than there are views" safety net and aborts the app.
//

import XCTest
@testable import Macintora

final class WindowLayoutPersisterTests: XCTestCase {

    // MARK: - paneSizesAreUsable

    func test_typicalRestore_isUsable() {
        // 800-wide split, two panes 200/600. Saved against the same
        // window — should restore cleanly.
        XCTAssertTrue(WindowLayoutPersister.paneSizesAreUsable(
            [200, 600], totalAxis: 800))
    }

    func test_threePanes_fitting_isUsable() {
        XCTAssertTrue(WindowLayoutPersister.paneSizesAreUsable(
            [200, 400, 200], totalAxis: 800))
    }

    func test_singlePane_isNotUsable() {
        // No divider to set; nothing to restore.
        XCTAssertFalse(WindowLayoutPersister.paneSizesAreUsable(
            [800], totalAxis: 800))
    }

    func test_zeroAxis_isNotUsable() {
        // The caller is expected to gate on this, but defence in depth.
        XCTAssertFalse(WindowLayoutPersister.paneSizesAreUsable(
            [200, 600], totalAxis: 0))
    }

    func test_savedOnWideMonitor_replayedOnNarrowWindow_isNotUsable() {
        // The user's reported reproducer: sizes saved against a wide
        // multi-monitor canvas (sum = 1800) replayed against the now-
        // single-monitor 864-wide window. Applying these would exceed
        // the available axis and trigger the constraint thrash.
        XCTAssertFalse(WindowLayoutPersister.paneSizesAreUsable(
            [400, 1400], totalAxis: 864))
    }

    func test_smallRoundingOvershoot_isUsable() {
        // Floating-point sums can drift a few points past the bounds
        // even when the user hasn't resized — allow a small overshoot
        // (5%) so legitimate restores aren't rejected.
        XCTAssertTrue(WindowLayoutPersister.paneSizesAreUsable(
            [400.5, 400.5], totalAxis: 800))
    }

    func test_largeOvershoot_isNotUsable() {
        XCTAssertFalse(WindowLayoutPersister.paneSizesAreUsable(
            [600, 600], totalAxis: 800))
    }

    func test_collapsedPaneBelowMin_isNotUsable() {
        // A pane below the min threshold (default 80) leaves the user
        // with an "invisible" pane only recoverable by dragging a
        // hairline divider — drop and let SwiftUI's default take over.
        XCTAssertFalse(WindowLayoutPersister.paneSizesAreUsable(
            [10, 790], totalAxis: 800))
    }

    func test_zeroPane_isNotUsable() {
        XCTAssertFalse(WindowLayoutPersister.paneSizesAreUsable(
            [0, 800], totalAxis: 800))
    }

    func test_negativePane_isNotUsable() {
        XCTAssertFalse(WindowLayoutPersister.paneSizesAreUsable(
            [-50, 850], totalAxis: 800))
    }

    func test_customMinPane_overridesDefault() {
        // A consumer that wants to allow tiny panes (e.g., a
        // collapse-friendly inspector) can lower the threshold.
        XCTAssertTrue(WindowLayoutPersister.paneSizesAreUsable(
            [10, 790], totalAxis: 800, minPane: 5))
    }
}
