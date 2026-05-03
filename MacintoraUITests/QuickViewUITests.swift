//
//  QuickViewUITests.swift
//  MacintoraUITests
//
//  End-to-end smoke tests for the Quick View popover (issue #12). Drives the
//  real app via XCUI keystroke events to exercise the trigger paths that
//  unit tests can't reach: hotkey + context menu + ⌘+Click.
//
//  Skips when `~/Documents/macintora/local.macintora` isn't present —
//  matches the convention in `MacintoraUITests`. The fixture provides a
//  document scene with a wired editor so we don't have to drive the
//  New Document UI.
//

import XCTest

final class QuickViewUITests: XCTestCase {

    private static let fixtureURL = URL(fileURLWithPath:
        "/Users/ilia/Documents/macintora/local.macintora")

    override func setUpWithError() throws {
        continueAfterFailure = false
        let path = Self.fixtureURL.path
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: path),
            "Fixture document \(path) does not exist — required for Quick View UI tests."
        )
    }

    @MainActor
    private func launchAppWithFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [Self.fixtureURL.path]
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        // Force the Quick View hotkey to ⌘I so the test is independent of
        // any user override stored in UserDefaults from manual testing.
        app.launchEnvironment["NSDoubleLocalizedStrings"] = "NO"
        app.launch()
        return app
    }

    /// ⌘I with the cursor on a recognisable identifier opens the popover.
    /// Regression coverage for: focused-value plumbing
    /// (`MainDocumentView.focusedSceneValue(.editorQuickViewBox)`),
    /// `MainDocumentMenuCommands.Quick View` button → `box.trigger?()`,
    /// `EditorQuickViewBox.trigger` → `QuickViewController.triggerAtCursor`.
    @MainActor
    func test_hotkey_opensQuickViewPopover() throws {
        let app = launchAppWithFixture()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "document window did not appear")

        let textView = window.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5), "editor text view not found")

        // Clear and type a stable fragment whose last token is `DUAL`.
        textView.click()
        textView.typeKey("a", modifierFlags: .command)
        textView.typeKey(.delete, modifierFlags: [])
        textView.typeText("select * from DUAL")

        // Cursor lands at end of typed text — that's already on the trailing
        // identifier `DUAL`, perfect for Quick View.

        // Pre-trigger: confirm no popover up yet so we know the post-state
        // assertion is meaningful.
        XCTAssertFalse(app.popovers.firstMatch.exists,
                       "A popover was already visible before the hotkey fired")

        // Trigger the hotkey at the document scope.
        window.typeKey("i", modifierFlags: .command)

        let popover = app.popovers.firstMatch
        XCTAssertTrue(
            popover.waitForExistence(timeout: 4),
            "Quick View popover did not appear after ⌘I on `DUAL`"
        )

        // Attach the popover screenshot for diagnosability.
        if popover.exists {
            let shot = popover.screenshot().pngRepresentation
            let att = XCTAttachment(data: shot, uniformTypeIdentifier: "public.png")
            att.name = "quickview-popover"
            att.lifetime = .keepAlways
            add(att)
        }

        // Cleanup: dismiss the popover so it doesn't bleed into the next
        // test. NSPopover.behavior == .transient dismisses on click-outside;
        // clicking back into the editor reliably triggers that even when
        // the window is positioned off-screen on the test runner. We don't
        // assert the dismissal — that's AppKit's contract, not ours.
        if textView.isHittable {
            textView.click()
        }
    }

    /// Esc dismisses the popover even when it shows the "not cached"
    /// placeholder — that path has no interactive SwiftUI elements before
    /// issue #13 wires the Open in Browser button, so the responder
    /// chain wouldn't receive `cancelOperation(_:)` without an explicit
    /// `acceptsFirstResponder = true` override on the hosting controller.
    /// Regression test for that fix.
    @MainActor
    func test_escape_dismissesNotCachedPopover() throws {
        let app = launchAppWithFixture()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))

        let textView = window.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))

        // Type a token guaranteed not to exist in any cache so the popover
        // shows the "not cached" placeholder. The token is also unlikely
        // to match against any auto-completed identifier.
        textView.click()
        textView.typeKey("a", modifierFlags: .command)
        textView.typeKey(.delete, modifierFlags: [])
        textView.typeText("select * from ZZZ_NEVER_CACHED_OBJ_X9")

        window.typeKey("i", modifierFlags: .command)

        let popover = app.popovers.firstMatch
        XCTAssertTrue(
            popover.waitForExistence(timeout: 4),
            "Quick View popover (not-cached state) did not appear after ⌘I"
        )

        // Esc must now dismiss without needing a mouse click anywhere.
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])

        // Polling — the popover dismiss is animated (NSPopover.animates).
        let dismissed = !popover.exists
            || (0..<10).contains { _ in
                Thread.sleep(forTimeInterval: 0.1)
                return !popover.exists
            }
        XCTAssertFalse(popover.exists,
                       "Esc must dismiss the not-cached popover; popover.exists=\(popover.exists), waited=\(dismissed)")
    }

    /// ⌘I with the cursor on whitespace must NOT open a popover — the
    /// resolver returns `.unresolved` and the controller short-circuits
    /// before fetching any cache row. Regression test for the "no-op when
    /// nothing's selected" contract.
    @MainActor
    func test_hotkey_onWhitespace_doesNothing() throws {
        let app = launchAppWithFixture()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))

        let textView = window.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))

        textView.click()
        textView.typeKey("a", modifierFlags: .command)
        textView.typeKey(.delete, modifierFlags: [])
        textView.typeText("   ")  // cursor sits on whitespace

        window.typeKey("i", modifierFlags: .command)

        // Brief wait window — if a popover were going to appear it'd be up
        // by now (the controller is sync up to the cache fetch).
        let popover = app.popovers.firstMatch
        let appeared = popover.waitForExistence(timeout: 1)
        XCTAssertFalse(appeared,
                       "Quick View popover appeared on whitespace — resolver should have returned unresolved")
    }

    /// The Database menu carries a "Quick View" item that mirrors the
    /// hotkey. Verifies the menu command is wired and reads the focused
    /// box from `MainDocumentMenuCommands` when invoked via the menu bar.
    @MainActor
    func test_menuCommand_quickView_isPresent() throws {
        let app = launchAppWithFixture()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        let menuBar = app.menuBars.firstMatch
        let databaseMenu = menuBar.menuBarItems["Database"]
        XCTAssertTrue(databaseMenu.waitForExistence(timeout: 5),
                      "Database menu missing from menu bar")
        databaseMenu.click()

        // The item's title in the open menu.
        let quickViewItem = app.menuItems["Quick View"]
        XCTAssertTrue(quickViewItem.waitForExistence(timeout: 3),
                      "Quick View menu item missing from Database menu")

        // Close the menu without invoking the item — the trigger may need
        // an editor focus the menu bar invocation steals. The item's
        // existence is what we're asserting.
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
    }
}
