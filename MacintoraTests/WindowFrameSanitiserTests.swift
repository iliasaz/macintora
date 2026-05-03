//
//  WindowFrameSanitiserTests.swift
//  MacintoraTests
//
//  Regression coverage for the launch-time crash where AppKit replays a
//  persisted window frame that lives off-screen (typically because a
//  secondary display was disconnected since the last save), and the
//  resulting NavigationSplitView layout drives
//  `_NSSplitViewItemViewWrapper.updateConstraints` past AppKit's
//  "more passes than there are views" safety net and aborts.
//
//  The user's reproducer was a saved frame at `{-2270, 143, 1100, 700}`
//  with no current screen at that position — that exact case is the
//  primary test below.
//

import XCTest
@testable import Macintora

final class WindowFrameSanitiserTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "com.iliasazonov.macintora.tests.window-frame-sanitiser"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - frameIsOnScreen

    func test_frameOnPrimary_isOnScreen() {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        XCTAssertTrue(WindowFrameSanitiser.frameIsOnScreen(
            CGRect(x: 100, y: 100, width: 800, height: 600),
            screens: [primary]))
    }

    func test_frameOnSecondaryToTheLeft_isOnScreen() {
        // 1920×1080 main + 1920×1080 secondary at x=-1920 (left of primary).
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let secondary = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let frame = CGRect(x: -1500, y: 100, width: 800, height: 600)
        XCTAssertTrue(WindowFrameSanitiser.frameIsOnScreen(frame,
                                                           screens: [primary, secondary]))
    }

    func test_userReproFrame_doesNotIntersectSingleScreen() {
        // The exact frame from the user's bug report: window at -2270,
        // extending to -1170. With only the primary 1920×1080 connected,
        // there's no overlap and the sanitiser must reject it.
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let badFrame = CGRect(x: -2270, y: 143, width: 1100, height: 700)
        XCTAssertFalse(WindowFrameSanitiser.frameIsOnScreen(badFrame,
                                                            screens: [primary]))
    }

    func test_smallSliverIntersection_isNotOnScreen() {
        // 50×50 sliver overlap doesn't clear the 100×100 minimum visible
        // area threshold — the window would be effectively unreachable.
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = CGRect(x: 1870, y: 1030, width: 800, height: 600)
        XCTAssertFalse(WindowFrameSanitiser.frameIsOnScreen(frame,
                                                            screens: [primary]))
    }

    func test_zeroSizeFrame_isNotOnScreen() {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = CGRect(x: 100, y: 100, width: 0, height: 0)
        XCTAssertFalse(WindowFrameSanitiser.frameIsOnScreen(frame,
                                                            screens: [primary]))
    }

    func test_noScreens_treatsEverythingAsOffScreen() {
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        XCTAssertFalse(WindowFrameSanitiser.frameIsOnScreen(frame, screens: []))
    }

    // MARK: - parseWindowFrame

    func test_parseWindowFrame_acceptsCanonicalFormat() {
        // `NSWindow.saveFrame(usingName:)` stores
        // "wx wy ww wh sx sy sw sh".
        let raw = "100 200 800 600 0 0 1920 1080"
        XCTAssertEqual(WindowFrameSanitiser.parseWindowFrame(from: raw),
                       CGRect(x: 100, y: 200, width: 800, height: 600))
    }

    func test_parseWindowFrame_acceptsNegativeOrigin() {
        let raw = "-2270 143 1100 700 -1920 0 1920 1080"
        XCTAssertEqual(WindowFrameSanitiser.parseWindowFrame(from: raw),
                       CGRect(x: -2270, y: 143, width: 1100, height: 700))
    }

    func test_parseWindowFrame_rejectsTooFewComponents() {
        XCTAssertNil(WindowFrameSanitiser.parseWindowFrame(from: "100 200"))
    }

    func test_parseWindowFrame_rejectsNonNumeric() {
        XCTAssertNil(WindowFrameSanitiser.parseWindowFrame(from: "abc def 100 200 0 0 1920 1080"))
    }

    func test_parseWindowFrame_rejectsZeroSize() {
        XCTAssertNil(WindowFrameSanitiser.parseWindowFrame(from: "100 200 0 0 0 0 1920 1080"))
    }

    // MARK: - Defaults sanitisation

    func test_sanitise_dropsOffScreenFrame_userRepro() {
        // The user's exact reproducer: bad frame saved, only the primary
        // display connected at launch.
        let key = "NSWindow Frame Macintora.MainDocument"
        defaults.set("-2270 143 1100 700 -2560 0 1440 900", forKey: key)

        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        WindowFrameSanitiser.sanitisePersistedFrames(
            autosaveNames: ["Macintora.MainDocument"],
            in: defaults,
            screenFrames: [primary])

        XCTAssertNil(defaults.string(forKey: key),
                     "Sanitiser must delete the off-screen entry so AppKit falls back to default placement")
    }

    func test_sanitise_keepsOnScreenFrame() {
        let key = "NSWindow Frame Macintora.MainDocument"
        let valid = "100 100 800 600 0 0 1920 1080"
        defaults.set(valid, forKey: key)

        WindowFrameSanitiser.sanitisePersistedFrames(
            autosaveNames: ["Macintora.MainDocument"],
            in: defaults,
            screenFrames: [CGRect(x: 0, y: 0, width: 1920, height: 1080)])

        XCTAssertEqual(defaults.string(forKey: key), valid,
                       "Valid persisted frame must survive sanitisation untouched")
    }

    func test_sanitise_keepsFrameOnSecondaryDisplay_whenSecondaryStillConnected() {
        let key = "NSWindow Frame Macintora.MainDocument"
        let onSecondary = "-1500 100 800 600 -1920 0 1920 1080"
        defaults.set(onSecondary, forKey: key)

        WindowFrameSanitiser.sanitisePersistedFrames(
            autosaveNames: ["Macintora.MainDocument"],
            in: defaults,
            screenFrames: [
                CGRect(x: 0, y: 0, width: 1920, height: 1080),
                CGRect(x: -1920, y: 0, width: 1920, height: 1080)
            ])

        XCTAssertNotNil(defaults.string(forKey: key))
    }

    func test_sanitise_dropsGarbageEntry() {
        let key = "NSWindow Frame Macintora.MainDocument"
        defaults.set("not a frame", forKey: key)

        WindowFrameSanitiser.sanitisePersistedFrames(
            autosaveNames: ["Macintora.MainDocument"],
            in: defaults,
            screenFrames: [CGRect(x: 0, y: 0, width: 1920, height: 1080)])

        XCTAssertNil(defaults.string(forKey: key),
                     "Unparseable persisted value must be cleared so AppKit doesn't try to interpret it")
    }

    func test_sanitise_isNoOpWhenNoEntryExists() {
        // No value set at all — sanitiser must not invent one.
        WindowFrameSanitiser.sanitisePersistedFrames(
            autosaveNames: ["Macintora.MainDocument"],
            in: defaults,
            screenFrames: [CGRect(x: 0, y: 0, width: 1920, height: 1080)])

        XCTAssertNil(defaults.string(forKey: "NSWindow Frame Macintora.MainDocument"))
    }

    func test_sanitise_handlesMultipleAutosaveNames() {
        defaults.set("-2270 143 1100 700 0 0 1920 1080", forKey: "NSWindow Frame DocA")
        defaults.set("100 100 800 600 0 0 1920 1080", forKey: "NSWindow Frame DocB")

        WindowFrameSanitiser.sanitisePersistedFrames(
            autosaveNames: ["DocA", "DocB"],
            in: defaults,
            screenFrames: [CGRect(x: 0, y: 0, width: 1920, height: 1080)])

        XCTAssertNil(defaults.string(forKey: "NSWindow Frame DocA"),
                     "Off-screen entry must be cleared")
        XCTAssertNotNil(defaults.string(forKey: "NSWindow Frame DocB"),
                        "On-screen entry must be preserved")
    }
}
