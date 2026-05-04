//
//  WindowLayoutPersister.swift
//  Macintora
//
//  Background view that hooks up persistence for the window frame and
//  `NSSplitView` divider positions used inside SwiftUI's `NavigationSplitView`
//  and `VSplitView`. SwiftUI doesn't surface these knobs, but the underlying
//  AppKit views do — we walk the content view tree to find them.
//
//  Window frame persistence uses AppKit's `setFrameAutosaveName(_:)`. Split
//  divider persistence is done manually (via UserDefaults + a notification
//  observer) because `NSSplitView.autosaveName` only restores from defaults
//  if it's set *before* the split view's first layout, which we can't
//  guarantee from outside SwiftUI.
//

import AppKit
import SwiftUI

struct WindowLayoutPersister: NSViewRepresentable {
    /// Smallest pane size we'll accept on restore. Below this any pane in
    /// the app is unusable (sidebar collapses, result grid disappears) and
    /// strongly suggests the saved sizes don't belong to the current
    /// layout.
    static let minPaneAxis: CGFloat = 80

    /// Pure validator for persisted pane sizes against the current split's
    /// total axis. Exposed for unit tests; the production caller is
    /// `AccessorView.restorePositions(for:key:)`.
    ///
    /// Returns `true` when the stored sizes can be applied without driving
    /// AppKit's constraint engine into the runaway update-pass loop that
    /// crashes the app at launch on monitor changes.
    ///
    /// Rules:
    /// - At least two panes (one divider).
    /// - Total axis is positive (caller has gated on this; included for
    ///   defence in depth).
    /// - Sum of stored sizes fits inside the current axis with a small
    ///   rounding overshoot allowance.
    /// - No pane is below `minPane` (would otherwise leave an invisible
    ///   pane the user can only recover by dragging a hairline divider).
    static func paneSizesAreUsable(_ sizes: [Double],
                                   totalAxis: CGFloat,
                                   minPane: CGFloat = WindowLayoutPersister.minPaneAxis) -> Bool {
        guard sizes.count > 1, totalAxis > 0 else { return false }
        let sum = sizes.reduce(0, +)
        guard sum > 0, sum <= Double(totalAxis) * 1.05 else { return false }
        return sizes.allSatisfy { $0 >= Double(minPane) }
    }

    let windowAutosaveName: String
    let splitAutosavePrefix: String

    func makeNSView(context: Context) -> NSView {
        let view = AccessorView()
        view.windowAutosaveName = windowAutosaveName
        view.splitAutosavePrefix = splitAutosavePrefix
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    @MainActor
    final class AccessorView: NSView {
        var windowAutosaveName: String = ""
        var splitAutosavePrefix: String = ""
        private var didConfigure = false
        private var splitObservers: [any NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // `NSView.window` is flagged as an unsafe construct in Swift 6.2
            // strict memory-safety mode (it reads through AppKit's runtime).
            // We're on the main actor here, so reading it is fine.
            guard !didConfigure, let window = unsafe self.window else { return }
            didConfigure = true
            // Skip persistence wiring entirely under XCTest. The autosave
            // round-trip can replay an off-screen frame from a prior session
            // (e.g., a disconnected secondary display), which sends AppKit's
            // constraint engine into a runaway update-pass loop and aborts
            // the host app before the test runner finishes bootstrapping.
            if Self.isRunningInTestHost { return }
            configureWindow(window)
            // Defer split-view discovery: SwiftUI may not have laid out the
            // NSSplitView descendants by the time this view enters the window.
            DispatchQueue.main.async { [weak self] in
                self?.configureSplitViews()
            }
        }

        private static var isRunningInTestHost: Bool {
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil {
                for observer in splitObservers {
                    NotificationCenter.default.removeObserver(observer)
                }
                splitObservers.removeAll()
                didConfigure = false
            }
        }

        // MARK: - Window frame

        private func configureWindow(_ window: NSWindow) {
            // First-launch sizing is owned by SwiftUI's
            // `.defaultSize(width:height:)` on the App scene (1100×700).
            // Forcing a manual half-screen `setFrame` here resized the
            // window mid-layout — which on monitor changes (where the
            // persisted frame had been dropped by `WindowFrameSanitiser`)
            // drove SwiftUI's NavigationSplitView constraint engine past
            // its update-pass budget and aborted the app at launch with
            // an `NSGenericException` ("more Update Constraints in Window
            // passes than there are views"). The autosave replay path
            // alone is safe: when the entry is missing, `defaultSize`
            // wins; when it's present, AppKit replays it before any
            // SwiftUI layout pass.
            window.setFrameAutosaveName(windowAutosaveName)
            // setFrameAutosaveName has already replayed any persisted frame.
            // If the persisted frame lived on a now-disconnected display, the
            // window can land entirely off-screen — at which point AppKit's
            // constraint engine thrashes ("more Update Constraints in Window
            // passes than there are views") and may even throw. Detect that
            // and snap the window back onto a visible screen.
            ensureFrameIsOnScreen(window)
        }

        /// If the window's frame doesn't intersect any connected screen by a
        /// reasonable margin, recenter it on the main screen at the default
        /// size and rewrite the autosave entry so the next launch is clean.
        private func ensureFrameIsOnScreen(_ window: NSWindow) {
            let frame = window.frame
            let screens = NSScreen.screens
            let minVisibleArea: CGFloat = 100 * 100
            let onScreen = screens.contains { screen in
                let intersection = frame.intersection(screen.visibleFrame)
                guard !intersection.isNull else { return false }
                return intersection.width * intersection.height >= minVisibleArea
            }
            guard !onScreen, let target = NSScreen.main ?? screens.first else { return }
            let visible = target.visibleFrame
            let width = min(frame.width > 0 ? frame.width : 1100, visible.width)
            let height = min(frame.height > 0 ? frame.height : 700, visible.height)
            let originX = visible.minX + (visible.width - width) / 2
            let originY = visible.minY + (visible.height - height) / 2
            window.setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: true)
            window.saveFrame(usingName: windowAutosaveName)
        }

        // MARK: - Split-view dividers

        private func configureSplitViews() {
            guard let contentView = unsafe window?.contentView else { return }
            let splits = collectSplitViews(in: contentView)
            for (index, split) in splits.enumerated() {
                let key = positionsKey(index: index)
                restorePositions(for: split, key: key)
                let observer = NotificationCenter.default.addObserver(
                    forName: NSSplitView.didResizeSubviewsNotification,
                    object: split,
                    queue: .main
                ) { [weak split] _ in
                    // The notification queue is `.main`, so we're on the main
                    // thread — assume the MainActor and call the @MainActor
                    // saver. The closure type itself is nonisolated, which is
                    // why the assumption is needed.
                    MainActor.assumeIsolated {
                        guard let split else { return }
                        Self.savePositions(for: split, key: key)
                    }
                }
                splitObservers.append(observer)
            }
        }

        private func collectSplitViews(in root: NSView) -> [NSSplitView] {
            var result: [NSSplitView] = []
            var stack: [NSView] = [root]
            while let view = stack.popLast() {
                if let split = view as? NSSplitView {
                    result.append(split)
                }
                stack.append(contentsOf: view.subviews)
            }
            return result
        }

        private func positionsKey(index: Int) -> String {
            "\(splitAutosavePrefix).\(index).paneSizes"
        }

        private func restorePositions(for split: NSSplitView, key: String) {
            guard let stored = UserDefaults.standard.array(forKey: key) as? [Double] else { return }
            // Pane structure changed since save (different SwiftUI view tree
            // or app version) — drop the slot so the next save writes a
            // fresh, matching layout.
            guard stored.count == split.arrangedSubviews.count, stored.count > 1 else {
                UserDefaults.standard.removeObject(forKey: key)
                return
            }
            // Bounds aren't laid out yet on this run; skip without dropping
            // so the sizes can be reused on a subsequent launch.
            let total = split.isVertical ? split.bounds.width : split.bounds.height
            guard total > 0 else { return }
            // Stored sizes are stale relative to current bounds — for
            // example, the user disconnected a wide external display and
            // the saved pane widths now exceed the available axis. Apply
            // them and AppKit thrashes the constraint engine
            // ("more Update Constraints in Window passes than there are
            // views") and aborts the app at launch.
            guard WindowLayoutPersister.paneSizesAreUsable(stored, totalAxis: total) else {
                UserDefaults.standard.removeObject(forKey: key)
                return
            }
            var cumulative: CGFloat = 0
            for i in 0..<(stored.count - 1) {
                cumulative += CGFloat(stored[i])
                split.setPosition(cumulative, ofDividerAt: i)
            }
        }

        private static func savePositions(for split: NSSplitView, key: String) {
            let sizes: [Double] = split.arrangedSubviews.map { sub in
                split.isVertical ? Double(sub.frame.width) : Double(sub.frame.height)
            }
            UserDefaults.standard.set(sizes, forKey: key)
        }
    }
}
