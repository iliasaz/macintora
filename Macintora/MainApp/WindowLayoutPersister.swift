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
            let frameKey = "NSWindow Frame \(windowAutosaveName)"
            if UserDefaults.standard.object(forKey: frameKey) == nil,
               let screen = window.screen ?? NSScreen.main {
                // First launch: roughly a quarter of the visible screen area
                // (half × half), centered.
                let visible = screen.visibleFrame
                let w = visible.width / 2
                let h = visible.height / 2
                let x = visible.minX + (visible.width - w) / 2
                let y = visible.minY + (visible.height - h) / 2
                window.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
            }
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
            guard let sizes = UserDefaults.standard.array(forKey: key) as? [Double] else { return }
            guard sizes.count == split.arrangedSubviews.count, sizes.count > 1 else { return }
            var cumulative: CGFloat = 0
            for i in 0..<(sizes.count - 1) {
                cumulative += CGFloat(sizes[i])
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
