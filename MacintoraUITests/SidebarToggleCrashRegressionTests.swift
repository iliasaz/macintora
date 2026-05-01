//
//  SidebarToggleCrashRegressionTests.swift
//  MacintoraUITests
//
//  Regression for the Auto Layout cycle that crashed the app whenever the
//  user toggled the NavigationSplitView sidebar after the script-runner
//  feature landed. The crash signature was:
//
//    NSGenericException — The window has been marked as needing another
//    Update Constraints in Window pass, but it has already had more Update
//    Constraints in Window passes than there are views in the window.
//
//  This test launches the fixture, toggles the sidebar twice via the
//  View menu, then exercises the editor — if the constraint loop returns,
//  the app dies and the post-toggle assertions fail.
//

import XCTest

final class SidebarToggleCrashRegressionTests: XCTestCase {

    private static let fixtureURL = URL(fileURLWithPath:
        "/Users/ilia/Documents/macintora/local.macintora")

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: Self.fixtureURL.path),
            "Fixture document does not exist — required for UI tests."
        )
    }

    @MainActor
    func test_togglingSidebarTwiceDoesNotCrash() throws {
        let app = XCUIApplication()
        app.launchArguments = [Self.fixtureURL.path]
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "document window did not appear")

        // Wait for the editor so we know layout has settled before toggling.
        let textView = window.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5), "editor text view not found")

        // Toggle sidebar via the standard AppKit selector. SwiftUI's
        // NavigationSplitView wires `View → Toggle Sidebar` to this.
        toggleSidebar(app: app)
        // Brief settle so any constraint-cycle crash has time to fire.
        usleep(200_000)
        XCTAssertTrue(app.state == .runningForeground, "app died after first sidebar toggle")
        XCTAssertTrue(window.exists, "window vanished after first sidebar toggle")

        toggleSidebar(app: app)
        usleep(200_000)
        XCTAssertTrue(app.state == .runningForeground, "app died after second sidebar toggle")
        XCTAssertTrue(window.exists, "window vanished after second sidebar toggle")

        // App must still be responsive — editor accepts focus and keystrokes.
        textView.click()
        textView.typeKey("a", modifierFlags: .command)
        textView.typeKey(.delete, modifierFlags: [])
        textView.typeText("OK")
        let contents = (textView.value as? String) ?? ""
        XCTAssertTrue(
            contents.contains("OK"),
            "editor unresponsive after sidebar toggles. value=\"\(contents)\""
        )
    }

    @MainActor
    private func toggleSidebar(app: XCUIApplication) {
        // Walk the menu bar: View → Show Sidebar / Hide Sidebar / Toggle Sidebar.
        let viewMenu = app.menuBars.menuBarItems["View"]
        guard viewMenu.waitForExistence(timeout: 2) else {
            XCTFail("View menu not found")
            return
        }
        viewMenu.click()
        let candidates = ["Show Sidebar", "Hide Sidebar", "Toggle Sidebar"]
        for label in candidates {
            let item = app.menus.menuItems[label]
            if item.exists, item.isHittable {
                item.click()
                return
            }
        }
        // Close the menu we opened if no item matched.
        viewMenu.click()
        XCTFail("No sidebar-toggle menu item found among: \(candidates)")
    }
}
