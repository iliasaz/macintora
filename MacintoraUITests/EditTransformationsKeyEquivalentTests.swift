import XCTest

/// Verifies that ⌘U and ⌘L are bound to AppKit's auto-injected
/// Edit > Transformations > Make Upper/Lower Case items and that pressing
/// the shortcuts transforms the editor's selection. Coverage for the
/// `installTransformationKeyEquivalents()` wiring in `MacintoraAppDelegate`.
final class EditTransformationsKeyEquivalentTests: XCTestCase {

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

    @MainActor
    private func launchAppWithFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [Self.fixtureURL.path]
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        app.launch()
        return app
    }

    @MainActor
    private func resetEditor(_ textView: XCUIElement) {
        textView.click()
        textView.typeKey("a", modifierFlags: .command)
        textView.typeKey(.delete, modifierFlags: [])
    }

    /// Pressing ⌘U at the cursor routes through `NSText.uppercaseWord(_:)`
    /// which selects and uppercases the word at the cursor.
    @MainActor
    func test_cmdU_uppercasesWordAtCursor() throws {
        let app = launchAppWithFixture()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "document window did not appear")

        let textView = window.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5), "editor text view not found")

        resetEditor(textView)
        textView.typeText("hello")
        // selectWord (called by STTextView's uppercaseWord) only expands to
        // the enclosing word when the cursor is *inside* it, not when it
        // sits at the trailing boundary. Step the caret back into "hello".
        textView.typeKey(.leftArrow, modifierFlags: [])
        textView.typeKey("u", modifierFlags: .command)

        let value = (textView.value as? String) ?? ""
        XCTAssertTrue(
            value.contains("HELLO"),
            "expected the word \"hello\" to be uppercased after ⌘U; got \"\(value)\""
        )
    }

    /// Pressing ⌘L at the cursor routes through `NSText.lowercaseWord(_:)`
    /// which selects and lowercases the word at the cursor.
    @MainActor
    func test_cmdL_lowercasesWordAtCursor() throws {
        let app = launchAppWithFixture()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "document window did not appear")

        let textView = window.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5), "editor text view not found")

        resetEditor(textView)
        textView.typeText("HELLO")
        textView.typeKey(.leftArrow, modifierFlags: [])
        textView.typeKey("l", modifierFlags: .command)

        let value = (textView.value as? String) ?? ""
        XCTAssertTrue(
            value.contains("hello"),
            "expected the word \"HELLO\" to be lowercased after ⌘L; got \"\(value)\""
        )
    }
}
