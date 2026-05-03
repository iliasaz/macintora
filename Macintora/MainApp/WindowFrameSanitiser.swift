//
//  WindowFrameSanitiser.swift
//  Macintora
//
//  Pre-launch validator for `NSWindow setFrameAutosaveName` entries
//  stored in `UserDefaults`. Exists because AppKit replays a saved
//  frame *before* SwiftUI's view tree wires up — if that frame doesn't
//  intersect any currently-connected screen, NavigationSplitView's
//  layout immediately drives `_NSSplitViewItemViewWrapper.updateConstraints`
//  past the "more passes than there are views" safety net and aborts
//  the app. The post-window check in `WindowLayoutPersister.ensureFrameIsOnScreen`
//  runs on `viewDidMoveToWindow`, which is too late for that case.
//
//  The sanitiser runs in `applicationWillFinishLaunching` before any
//  document window is created, so the bad UserDefaults entry never
//  gets a chance to drive layout.
//
//  Format note: `NSWindow.saveFrame(usingName:)` writes the value as
//  a single string of eight space-separated numbers —
//  "wx wy ww wh sx sy sw sh", the first four being the window frame
//  and the last four the visible screen frame at save time. We only
//  need the window frame to validate against current screens.
//

import AppKit
import Foundation

enum WindowFrameSanitiser {

    /// Reads `NSWindow Frame {autosaveName}` for each name in
    /// `autosaveNames`, verifies the window frame intersects at least one
    /// of the supplied `screens` by a meaningful amount, and deletes the
    /// defaults entry when it doesn't. Deleting is safer than rewriting
    /// the value: the next window launch falls back to AppKit's default
    /// placement (centered on the main screen), which is always valid.
    ///
    /// Exposed as a static helper so unit tests can drive it with a
    /// scratch `UserDefaults` and synthesised `NSScreen` substitutes.
    static func sanitisePersistedFrames(autosaveNames: [String],
                                        in defaults: UserDefaults,
                                        screens: [NSScreen]) {
        let visibleFrames = screens.map(\.visibleFrame)
        for name in autosaveNames {
            sanitise(autosaveName: name, defaults: defaults, screens: visibleFrames)
        }
    }

    /// Test-friendly overload that accepts plain `CGRect` screens — lets
    /// tests run without instantiating `NSScreen`.
    static func sanitisePersistedFrames(autosaveNames: [String],
                                        in defaults: UserDefaults,
                                        screenFrames: [CGRect]) {
        for name in autosaveNames {
            sanitise(autosaveName: name, defaults: defaults, screens: screenFrames)
        }
    }

    /// `true` when `frame` intersects at least one of `screens` by the
    /// minimum visible area threshold. Centralised so production and tests
    /// agree on the rule.
    static func frameIsOnScreen(_ frame: CGRect, screens: [CGRect]) -> Bool {
        let minVisibleArea: CGFloat = 100 * 100
        return screens.contains { screen in
            let intersection = frame.intersection(screen)
            guard !intersection.isNull, !intersection.isEmpty else { return false }
            return intersection.width * intersection.height >= minVisibleArea
        }
    }

    /// Parses an `NSWindow.saveFrame(usingName:)`-style 8-number string
    /// and returns the window frame portion (first four numbers). Returns
    /// `nil` for any malformed input so callers can decide whether to
    /// keep or drop the defaults entry.
    static func parseWindowFrame(from value: String) -> CGRect? {
        let components = value.split(whereSeparator: { $0.isWhitespace })
        guard components.count >= 4 else { return nil }
        guard let x = Double(components[0]),
              let y = Double(components[1]),
              let w = Double(components[2]),
              let h = Double(components[3]),
              w > 0, h > 0 else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Internals

    private static func sanitise(autosaveName: String,
                                 defaults: UserDefaults,
                                 screens: [CGRect]) {
        let key = "NSWindow Frame \(autosaveName)"
        guard let raw = defaults.string(forKey: key) else { return }
        guard let frame = parseWindowFrame(from: raw) else {
            // Garbage value — drop it.
            defaults.removeObject(forKey: key)
            return
        }
        if !frameIsOnScreen(frame, screens: screens) {
            defaults.removeObject(forKey: key)
        }
    }
}
