//
//  ScriptRunnerUXTests.swift
//  MacintoraUITests
//
//  XCUITest coverage for the script-runner toolbar buttons, the substitution
//  prompt sheet, and the script-output pane swap. Reuses the same fixture
//  document as the legacy `MacintoraUITests` and assumes a TNS alias `local`
//  is reachable for connection-dependent flows.
//

import XCTest

final class ScriptRunnerUXTests: XCTestCase {

    private static let fixtureURL = URL(fileURLWithPath:
        "/Users/ilia/Documents/macintora/local.macintora")

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: Self.fixtureURL.path),
            "Fixture document required for UI tests."
        )
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [Self.fixtureURL.path]
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        app.launch()
        return app
    }

    // MARK: - Toolbar buttons exist and are reachable

    @MainActor
    func test_runScriptToolbarButtonsExist() throws {
        let app = launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))

        let runScript = window.toolbars.buttons["toolbar.runScript"]
        XCTAssertTrue(runScript.waitForExistence(timeout: 5), "Run Script toolbar button missing")
        let runFromCursor = window.toolbars.buttons["toolbar.runScriptFromCursor"]
        XCTAssertTrue(runFromCursor.waitForExistence(timeout: 5), "Run From Cursor toolbar button missing")
    }

    // MARK: - Substitution sheet on `&` variables

    @MainActor
    func test_substitutionSheetAppearsForAmpersandVariable() throws {
        let app = launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))

        // Connect — the runner only kicks off if the document has a connection.
        let connectButton = window.toolbars.buttons["toolbar.connect"]
        guard connectButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Connect toolbar button not found.")
        }
        connectButton.click()
        let disconnectButton = window.toolbars.buttons["toolbar.disconnect"]
        guard disconnectButton.waitForExistence(timeout: 30) else {
            throw XCTSkip("Could not connect to TNS alias `local` — substitution-sheet UX test requires a live DB.")
        }

        // Replace the editor body with a script that references `&owner`.
        let textView = window.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.click()
        textView.typeKey("a", modifierFlags: .command)
        textView.typeKey(.delete, modifierFlags: [])
        textView.typeText("SELECT '&owner' AS o FROM dual;")

        // Cmd-Shift-R triggers Run Script.
        window.typeKey("r", modifierFlags: [.command, .shift])

        // The substitution sheet should appear.
        let sheet = app.descendants(matching: .any)["script.substitutionSheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "expected substitution sheet to appear for &owner")

        // Cancel dismisses the sheet without running the script.
        let cancel = app.buttons["script.substitutionSheet.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 2))
        cancel.click()

        // Sheet goes away.
        XCTAssertFalse(sheet.waitForExistence(timeout: 2), "sheet should have dismissed on Cancel")
    }

    // MARK: - Script-output pane swap

    @MainActor
    func test_runScriptSwapsToScriptOutputPane() throws {
        let app = launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))

        // Need a live connection for runScript to actually fire.
        let connectButton = window.toolbars.buttons["toolbar.connect"]
        guard connectButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Connect toolbar button not found.")
        }
        connectButton.click()
        let disconnectButton = window.toolbars.buttons["toolbar.disconnect"]
        guard disconnectButton.waitForExistence(timeout: 30) else {
            throw XCTSkip("Could not connect to TNS alias `local`.")
        }

        // Type a single-statement script (no `&`, no `:bind` — runs immediately).
        let textView = window.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.click()
        textView.typeKey("a", modifierFlags: .command)
        textView.typeKey(.delete, modifierFlags: [])
        textView.typeText("SELECT 1 FROM dual;")

        window.typeKey("r", modifierFlags: [.command, .shift])

        let pane = app.descendants(matching: .any)["scriptOutput.pane"]
        XCTAssertTrue(pane.waitForExistence(timeout: 5), "expected script output pane to appear after Cmd-Shift-R")
    }
}
