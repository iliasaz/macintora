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
    /// actually land in the view AND actually render on screen.
    ///
    /// Checking `XCUIElement.value` alone is a false positive — that reads the
    /// text storage, which can hold characters even when TextKit 2 fails to
    /// render them. We also screenshot the editor rect before and after
    /// typing and assert that the pixel content changed — i.e. characters
    /// actually appeared on screen.
    @MainActor
    func test_typingInEditorShowsCharacters() throws {
        let app = launchAppWithFixture()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "document window did not appear")

        let textView = window.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5), "editor text view not found")

        textView.click()
        textView.typeKey("a", modifierFlags: .command)
        textView.typeKey(.delete, modifierFlags: [])

        // Empty editor baseline screenshot.
        let beforeData = textView.screenshot().pngRepresentation
        XCTAssertFalse(beforeData.isEmpty, "could not grab 'before' screenshot")

        let typed = "SELECT 42 FROM DUAL"
        textView.typeText(typed)

        // Storage check — quick sanity test (will pass even when rendering
        // is broken, but gives a clearer failure if the input events never
        // reached the text view at all).
        let contents = (textView.value as? String) ?? ""
        XCTAssertTrue(
            contents.contains(typed),
            "editor storage does not contain typed text. value=\"\(contents)\""
        )

        // Rendering check — if the typed characters actually drew, the editor
        // screenshot must be materially different from the empty baseline.
        let afterData = textView.screenshot().pngRepresentation
        XCTAssertFalse(afterData.isEmpty, "could not grab 'after' screenshot")

        // Raw PNG byte comparison is enough: identical images compress to
        // identical PNGs. A single rendered glyph changes many bytes.
        XCTAssertNotEqual(
            beforeData, afterData,
            """
            Editor looks identical before and after typing "\(typed)".
            Storage has the text (value=\"\(contents)\") but nothing rendered
            on screen — the TextKit 2 layout path is broken.
            """
        )

        // Attach both screenshots to the test result so failures are
        // diagnosable without having to re-run interactively.
        let beforeAttachment = XCTAttachment(data: beforeData, uniformTypeIdentifier: "public.png")
        beforeAttachment.name = "editor-before-typing"
        beforeAttachment.lifetime = .keepAlways
        add(beforeAttachment)

        let afterAttachment = XCTAttachment(data: afterData, uniformTypeIdentifier: "public.png")
        afterAttachment.name = "editor-after-typing"
        afterAttachment.lifetime = .keepAlways
        add(afterAttachment)
    }

    /// Full oracle-nio migration validation: open a saved document with a
    /// known TNS connection, click Connect, type a simple query, click Run,
    /// verify "42" shows up in the result grid, save, close.
    ///
    /// Requires a reachable Oracle DB under the `local` TNS alias configured
    /// in the user's `tnsnames.ora`. Fails (doesn't skip) if the result
    /// doesn't come back — this is the "migration works" acceptance test.
    @MainActor
    func test_endToEnd_openConnectQueryAndSave() throws {
        let app = launchAppWithFixture()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "document window did not appear")

        // 1. Wait for the editor.
        let textView = window.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5), "editor text view not found")

        // 2. Connect to the DB. The connect/disconnect toolbar button is
        //    identified via `.accessibilityIdentifier("toolbar.connect"/
        //    "toolbar.disconnect")` in MainDocumentView.
        let connectButton = window.toolbars.buttons["toolbar.connect"]
        if !connectButton.waitForExistence(timeout: 5) {
            XCTFail("Connect toolbar button not found. Toolbar tree:\n\(window.toolbars.firstMatch.debugDescription)")
            return
        }
        connectButton.click()

        // The button's identifier flips to `toolbar.disconnect` once
        // connected. 30 s accommodates TCP handshake + Oracle auth.
        let disconnectButton = window.toolbars.buttons["toolbar.disconnect"]
        XCTAssertTrue(
            disconnectButton.waitForExistence(timeout: 30),
            "Did not reach connected state. Check tnsnames.ora alias `local` and credentials in \(Self.fixtureURL.path)."
        )

        // 3. Clear the editor, type the query.
        textView.click()
        textView.typeKey("a", modifierFlags: .command)
        textView.typeKey(.delete, modifierFlags: [])
        textView.typeText("select 42 from dual;")

        // Sanity check the storage before we hit Run.
        let editorContents = (textView.value as? String) ?? ""
        XCTAssertTrue(
            editorContents.contains("select 42 from dual;"),
            "Editor storage missing typed query. value=\"\(editorContents)\""
        )

        // 4. Execute. Run is Cmd-R in Macintora; also available as a toolbar
        //    button but the keyboard shortcut is the fastest route.
        window.typeKey("r", modifierFlags: .command)

        // 5. Wait for "42" to surface in the result view. The result is an
        //    NSTableView-backed grid; `descendants(matching: .any).matching
        //    (identifier: "42")` catches whichever accessibility surface it
        //    gets exposed as. Poll for up to 15 s for the result to arrive.
        let fortyTwo = window.staticTexts["42"]
        let foundViaStatic = fortyTwo.waitForExistence(timeout: 15)
        let foundViaCell = !foundViaStatic
            ? window.cells.containing(NSPredicate(format: "value CONTAINS[c] '42'")).firstMatch
                .waitForExistence(timeout: 5)
            : true

        // Always attach a post-query screenshot so a failing run is diagnosable.
        let resultShot = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: resultShot, uniformTypeIdentifier: "public.png")
        attachment.name = "after-run"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertTrue(
            foundViaStatic || foundViaCell,
            "Did not find `42` in the result view after executing the query."
        )

        // 6. Save. NSDocument's `save:` is ⌘S.
        window.typeKey("s", modifierFlags: .command)

        // Give autosave + file write a beat, then assert the Edited badge in
        // the title went away. Title changes from "local • Edited" or similar
        // back to just "local" once save completes.
        let savedPredicate = NSPredicate(format: "title CONTAINS[c] 'local'")
        let savedWindow = window
        _ = savedWindow.waitForExistence(timeout: 3) // settle
        let postSaveTitle = savedWindow.title
        XCTAssertFalse(
            postSaveTitle.lowercased().contains("edited"),
            "Document still shows 'Edited' after ⌘S. Title=\"\(postSaveTitle)\""
        )
        _ = savedPredicate

        // 7. Close the document (⌘W). If there were unsaved changes a
        //    "Do you want to save" sheet would pop — we just asserted we
        //    saved so Close should be clean.
        window.typeKey("w", modifierFlags: .command)
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
