//
//  EditorShortcutsUITests.swift
//  MacintoraUITests
//
//  Verifies every Macintora-specific keyboard shortcut wired by the
//  menu bar (issue #24) actually reaches its action site when pressed.
//  We don't need to run the real `runScript`, open Settings, or toggle
//  comments here — that's covered by unit tests and the standalone
//  `EditTransformationsKeyEquivalentTests` / `QuickViewUITests`. The job
//  of this suite is to catch dispatch regressions in the menu wiring.
//
//  Mechanism: the app, when launched with `-uiTestProbe`, records the
//  fired command name on `UITestProbe.shared.lastCommand` and suppresses
//  the real side effect. A hidden SwiftUI `Text` with accessibility
//  identifier `"ui_test_probe.last_command"` carries the recorded value
//  back to XCUITest. The Stop test additionally passes
//  `-uiTestForceExecuting` to flip the menu's executing gate on.
//
//  Skips when the local fixture document is missing — same convention as
//  the existing UI tests so this suite stays runnable on machines without
//  test fixtures provisioned.
//

import XCTest

final class EditorShortcutsUITests: XCTestCase {

    private static let fixtureURL = URL(fileURLWithPath:
        "/Users/ilia/Documents/macintora/local.macintora")
    private static let probeIdentifier = "ui_test_probe.last_command"

    override func setUpWithError() throws {
        continueAfterFailure = false
        let path = Self.fixtureURL.path
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: path),
            "Fixture document \(path) does not exist — required for UI tests."
        )
    }

    // MARK: - Helpers

    @MainActor
    private func launchAppWithProbe(forceExecuting: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var args = [Self.fixtureURL.path, "-uiTestProbe"]
        if forceExecuting { args.append("-uiTestForceExecuting") }
        app.launchArguments = args
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        app.launch()
        return app
    }

    /// Press the shortcut at the document window and wait for the probe's
    /// `accessibilityValue` to equal `expected`. The probe is a hidden
    /// SwiftUI `Text` whose `.value` reflects `UITestProbe.lastCommand`.
    @MainActor
    private func assertShortcutFires(
        _ expected: String,
        on app: XCUIApplication,
        key: String,
        modifiers: XCUIElement.KeyModifierFlags,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let window = app.windows.firstMatch
        XCTAssertTrue(
            window.waitForExistence(timeout: 10),
            "document window did not appear",
            file: file, line: line
        )

        // The editor needs focus so the document scene's menu dispatch
        // sees the right `@FocusedSceneValue` cohort.
        let textView = window.textViews.firstMatch
        XCTAssertTrue(
            textView.waitForExistence(timeout: 5),
            "editor text view not found",
            file: file, line: line
        )
        textView.click()

        let probe = app.descendants(matching: .any).matching(identifier: Self.probeIdentifier).firstMatch
        XCTAssertTrue(
            probe.waitForExistence(timeout: 5),
            "UI test probe not found — was the app launched with -uiTestProbe?",
            file: file, line: line
        )

        window.typeKey(key, modifierFlags: modifiers)

        // Poll the probe's accessibility value rather than reading once — the
        // menu dispatch is asynchronous and the `@Observable` republish takes
        // a tick or two to propagate through SwiftUI.
        let predicate = NSPredicate(format: "value == %@", expected)
        let probed = XCTNSPredicateExpectation(predicate: predicate, object: probe)
        let result = XCTWaiter().wait(for: [probed], timeout: 4)
        XCTAssertEqual(
            result, .completed,
            "expected the probe to record \"\(expected)\" within 4s after pressing the shortcut; got \"\(String(describing: probe.value))\"",
            file: file, line: line
        )
    }

    // MARK: - Run group

    @MainActor
    func test_cmd_R_fires_run() throws {
        let app = launchAppWithProbe()
        assertShortcutFires("Run", on: app, key: "r", modifiers: .command)
    }

    @MainActor
    func test_cmd_B_fires_stop() throws {
        // Stop is enabled only when `worksheetIsExecuting == true`. The
        // probe synthesises that state without a live DB connection.
        let app = launchAppWithProbe(forceExecuting: true)
        assertShortcutFires("Stop", on: app, key: "b", modifiers: .command)
    }

    @MainActor
    func test_shiftCmd_R_fires_run_script() throws {
        let app = launchAppWithProbe()
        assertShortcutFires("Run Script", on: app, key: "r", modifiers: [.command, .shift])
    }

    @MainActor
    func test_optCmd_R_fires_run_from_cursor_or_selection() throws {
        let app = launchAppWithProbe()
        assertShortcutFires(
            "Run From Cursor / Selection",
            on: app, key: "r", modifiers: [.command, .option]
        )
    }

    @MainActor
    func test_cmd_E_fires_explain_plan() throws {
        let app = launchAppWithProbe()
        assertShortcutFires("Explain Plan", on: app, key: "e", modifiers: .command)
    }

    @MainActor
    func test_optCmd_C_fires_compile() throws {
        let app = launchAppWithProbe()
        assertShortcutFires("Compile", on: app, key: "c", modifiers: [.command, .option])
    }

    @MainActor
    func test_ctrlCmd_F_fires_format() throws {
        let app = launchAppWithProbe()
        assertShortcutFires("Format", on: app, key: "f", modifiers: [.command, .control])
    }

    // MARK: - Editor

    @MainActor
    func test_cmd_slash_fires_toggle_line_comment() throws {
        let app = launchAppWithProbe()
        assertShortcutFires(
            "Toggle Line Comment",
            on: app, key: "/", modifiers: .command
        )
    }

    // MARK: - Database

    @MainActor
    func test_shiftCmd_K_fires_manage_connections() throws {
        let app = launchAppWithProbe()
        assertShortcutFires(
            "Manage Connections",
            on: app, key: "k", modifiers: [.command, .shift]
        )
    }

    @MainActor
    func test_shiftCmd_I_fires_database_browser() throws {
        let app = launchAppWithProbe()
        assertShortcutFires(
            "Database Browser",
            on: app, key: "i", modifiers: [.command, .shift]
        )
    }

    @MainActor
    func test_ctrlShiftCmd_S_fires_session_browser() throws {
        let app = launchAppWithProbe()
        assertShortcutFires(
            "Session Browser",
            on: app, key: "s", modifiers: [.command, .control, .shift]
        )
    }

    // MARK: - File / Toolbar

    @MainActor
    func test_shiftCmd_T_fires_new_tab_from_selection() throws {
        // ⇧⌘T lives on the toolbar button (copy current SQL into a new tab),
        // not the ⌘T `CommandGroup(after: .newItem)` blank-tab entry. The
        // probe label distinguishes the two so this test can't accidentally
        // pass against the wrong source.
        let app = launchAppWithProbe()
        assertShortcutFires(
            "New Tab from Selection",
            on: app, key: "t", modifiers: [.command, .shift]
        )
    }
}
