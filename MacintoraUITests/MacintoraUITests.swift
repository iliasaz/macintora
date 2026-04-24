import XCTest

/// End-to-end UX tests that launch the app and drive the real NSTextView via
/// keystroke events. These are the "does the editor actually accept typing"
/// regression tests.
///
/// Opens `~/Documents/macintora/local.macintora` instead of relying on the
/// New Document / Open File dialog — the fixture the user keeps around for
/// quick smoke testing.
final class MacintoraUITests: XCTestCase {

    // Absolute path to the fixture — the test runner is sandboxed so `~` does
    // not resolve to the developer's real home directory.
    private static let fixtureURL = URL(fileURLWithPath:
        "/Users/ilia/Documents/macintora/local.macintora")

    override func setUpWithError() throws {
        continueAfterFailure = false
        let path = Self.fixtureURL.path
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: path),
            "Fixture document \(path) does not exist — required for UI tests."
        )
    }

    /// Launch the app with the fixture document preloaded. Waits until
    /// either the main window with the editor appears or we hit a timeout.
    @MainActor
    private func launchAppWithFixture() -> XCUIApplication {
        let app = XCUIApplication()
        // Passing the file path as a plain launch argument tells NSApplication
        // to open that document on startup, skipping the new-document UI.
        app.launchArguments = [Self.fixtureURL.path]
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        app.launch()
        return app
    }

    /// The regression test: type into the editor and verify the characters
    /// actually land in the view. Reproduces the "text is captured (document
    /// goes to Edited) but nothing appears on screen" failure.
    @MainActor
    func test_typingInEditorShowsCharacters() throws {
        let app = launchAppWithFixture()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "document window did not appear")

        let textView = window.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5), "editor text view not found")

        textView.click()
        // Select all then delete to start from a known empty editor.
        textView.typeKey("a", modifierFlags: .command)
        textView.typeKey(.delete, modifierFlags: [])

        let typed = "SELECT 42 FROM DUAL"
        textView.typeText(typed)

        // XCUIElement.value for an NSTextView is the current text. If typing
        // worked, `typed` is somewhere in that value.
        let contents = (textView.value as? String) ?? ""
        XCTAssertTrue(
            contents.contains(typed),
            "editor does not contain typed text. value=\"\(contents)\""
        )
    }

    /// Baseline: a newline should still advance the line count. The user
    /// reported this works even while regular characters don't, so this test
    /// should pass independently of the typing fix.
    @MainActor
    func test_pressingReturnAdvancesLines() throws {
        let app = launchAppWithFixture()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let textView = window.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))

        textView.click()
        textView.typeKey("a", modifierFlags: .command)
        textView.typeKey(.delete, modifierFlags: [])

        textView.typeKey(.return, modifierFlags: [])
        textView.typeKey(.return, modifierFlags: [])

        let contents = (textView.value as? String) ?? ""
        XCTAssertTrue(
            contents.contains("\n\n") || contents.count >= 2,
            "newlines didn't register. value=\"\(contents)\""
        )
    }
}
