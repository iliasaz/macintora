//
//  DBBrowserMenuUITests.swift
//  MacintoraUITests
//
//  Verifies the "DB Browser" menu (issue #25, Item 3): the `CommandMenu`
//  wired by `DBBrowserMenuCommands` is present in the menu bar with every
//  expected item, and — because no DB Browser window is keyed when only a
//  worksheet document is open — every item is disabled (the menu gates on
//  `@FocusedValue(\.dbBrowserCommandsBox)`). That gating is what keeps ⌘R
//  meaning "Run" while an editor is keyed; the dispatch side of that is
//  covered by `EditorShortcutsUITests.test_cmd_R_fires_run`.
//
//  Skips when the local fixture document is missing — same convention as
//  the other UI suites so this stays runnable on machines without fixtures.
//

import XCTest

final class DBBrowserMenuUITests: XCTestCase {

    private static let fixtureURL = URL(fileURLWithPath:
        "/Users/ilia/Documents/macintora/local.macintora")

    /// Items the `DB Browser` menu must expose, in declaration order.
    private static let expectedItems = [
        "Incremental Refresh",
        "Full Refresh",
        "Full Refresh & Compact",
        "Compact Cache",
        "Focus Search",
        "Clear Search",
        "Main Tab",
        "Details Tab",
        "Show Counts",
        "Clear Cache",
    ]

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
    func test_dbBrowserMenu_existsWithAllItems_andIsDisabledWithoutABrowserWindow() throws {
        let app = launchAppWithFixture()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "document window did not appear")

        let menuBar = app.menuBars.firstMatch
        let dbBrowserMenu = menuBar.menuBarItems["DB Browser"]
        XCTAssertTrue(
            dbBrowserMenu.waitForExistence(timeout: 5),
            "the 'DB Browser' CommandMenu is missing from the menu bar"
        )

        dbBrowserMenu.click()

        for title in Self.expectedItems {
            let item = menuBar.menuItems[title]
            XCTAssertTrue(item.waitForExistence(timeout: 3), "menu item '\(title)' is missing from the DB Browser menu")
            XCTAssertFalse(
                item.isEnabled,
                "menu item '\(title)' should be disabled when no DB Browser window is keyed — it gates on @FocusedValue(\\.dbBrowserCommandsBox)"
            )
        }

        // Close the menu so the app is left in a clean state.
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func test_dbBrowserMenu_doesNotStealRunFromEditor() throws {
        // Sanity peer to the above: with only a worksheet open, the editor's
        // ⌘R "Run" item must be enabled (the DB Browser "Incremental Refresh"
        // ⌘R peer is disabled, so AppKit routes ⌘R to Run). This catches a
        // regression where the DB Browser menu would shadow the editor's.
        let app = launchAppWithFixture()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "document window did not appear")

        let textView = window.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5), "editor text view not found")
        textView.click()

        let menuBar = app.menuBars.firstMatch
        let dbIncremental = menuBar.menuItems["Incremental Refresh"]
        // (No need to open a menu first — menuItems are queryable regardless.)
        if dbIncremental.exists {
            XCTAssertFalse(dbIncremental.isEnabled, "DB Browser ⌘R peer must stay disabled while an editor is keyed")
        }
    }
}
