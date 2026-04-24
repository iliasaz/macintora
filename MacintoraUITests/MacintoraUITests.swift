import XCTest

/// End-to-end UX tests that launch the app and drive the real NSTextView via
/// keystroke events. These are the "does the editor actually accept typing"
/// regression tests.
///
/// Runs against the `Macintora` target; the UI test runner boots a fresh
/// instance for each test so state doesn't leak between scenarios.
final class MacintoraUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The regression test the user asked for: launch the app and type into
    /// the code editor. The typed text must appear in the text view.
    @MainActor
    func test_typingInEditorShowsCharacters() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en-US)", "-AppleLocale", "en_US"]
        app.launch()

        // Macintora uses a SwiftUI `DocumentGroup` so launch lands on an empty
        // "Untitled" document with the code editor focused after ~0.75s.
        // The editor is the first NSTextView inside the document window.
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "app window did not appear")

        let textView = window.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5), "editor text view not found")

        // Click to focus, clear any starter-text selection, then type.
        textView.click()
        // Select all + delete to get a clean slate (the default document
        // contains an example `select user, systimestamp, ...` query).
        textView.typeKey("a", modifierFlags: .command)
        textView.typeKey(.delete, modifierFlags: [])

        let typed = "SELECT 42 FROM DUAL"
        textView.typeText(typed)

        // Read back the editor contents. XCUIElement.value is the text for
        // NSTextView-backed controls.
        let contents = (textView.value as? String) ?? ""
        XCTAssertTrue(
            contents.contains(typed),
            "editor does not contain typed text. value=\"\(contents)\""
        )
    }

    /// Sanity check that a pure newline works — the user reported this still
    /// functions even when regular characters don't, so this test should pass
    /// even in the broken state and gives us a baseline.
    @MainActor
    func test_pressingReturnAddsNewLine() throws {
        let app = XCUIApplication()
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
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
