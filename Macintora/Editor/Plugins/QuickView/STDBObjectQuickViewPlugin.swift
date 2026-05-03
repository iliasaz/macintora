//
//  STDBObjectQuickViewPlugin.swift
//  Macintora
//
//  STTextView plugin that wires three trigger paths into a single
//  `QuickViewController`:
//
//    1. Right-click — adds a "Quick View" item to the standard context menu
//       via `STPluginEvents.onContextMenu`. STTextView appends single-item
//       plugin menus to its own menu (with a separator) — see
//       `STTextViewDelegateProxy.swift` upstream — so we don't replace the
//       built-in actions.
//
//    2. ⌘+Click — installed as an `NSEvent.addLocalMonitorForEvents` monitor
//       scoped to the text view's window. Returns the original event so the
//       click still moves the cursor; no text selection is consumed.
//
//    3. Hotkey — handled outside the plugin (focused-value action published
//       by `MainDocumentView` and consumed by the SwiftUI menu command).
//       Routed back here through the controller exposed on the editor's
//       coordinator.
//

import AppKit
import STTextView

@MainActor
struct STDBObjectQuickViewPlugin: STPlugin {
    let controller: QuickViewController

    init(controller: QuickViewController) {
        self.controller = controller
    }

    func setUp(context: any Context) {
        let textView = context.textView
        let controller = self.controller
        let coordinator = context.coordinator
        coordinator.installCmdClickMonitor(textView: textView, controller: controller)

        // STTextView doesn't retain `Coordinator` directly. The contract
        // (see `NeonPlugin.setUp`) is that an `events` closure captures it
        // strongly so the long-lived `STPluginEvents` keeps it alive — and
        // with it, the cmd+click monitor whose token only the coordinator
        // holds. Drop this capture and the monitor dies when `setUp` returns.
        context.events.onContextMenu { [coordinator] location, contentManager in
            _ = coordinator
            let menu = NSMenu()
            let utf16Offset = contentManager.offset(
                from: contentManager.documentRange.location,
                to: location)

            // "Quick View" item
            let qvTarget = QuickViewMenuTarget { [weak controller, weak textView] in
                guard let controller, let textView else { return }
                controller.triggerAtTextLocation(textView: textView,
                                                 utf16Offset: utf16Offset)
            }
            let qvItem = NSMenuItem(title: "Quick View", action: nil, keyEquivalent: "")
            qvItem.target = qvTarget
            qvItem.action = #selector(QuickViewMenuTarget.invoke(_:))
            qvItem.representedObject = qvTarget
            menu.addItem(qvItem)

            // "Show in DB Browser" item — sibling of Quick View
            let browserTarget = QuickViewMenuTarget { [weak controller, weak textView] in
                guard let controller, let textView else { return }
                controller.openInBrowserAtTextLocation(textView: textView,
                                                       utf16Offset: utf16Offset)
            }
            let browserItem = NSMenuItem(title: "Show in DB Browser", action: nil, keyEquivalent: "")
            browserItem.target = browserTarget
            browserItem.action = #selector(QuickViewMenuTarget.invoke(_:))
            browserItem.representedObject = browserTarget
            menu.addItem(browserItem)

            return menu
        }
    }

    func makeCoordinator(context: CoordinatorContext) -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        /// Token returned by `NSEvent.addLocalMonitorForEvents`. Read and
        /// written only on the main actor; the matching `removeMonitor`
        /// call also runs on main — see `isolated deinit` below.
        private var monitor: Any?

        func installCmdClickMonitor(textView: STTextView,
                                    controller: QuickViewController) {
            // Only one monitor per coordinator instance; tearDown removes it.
            removeMonitor()
            // ⌘+Click hit-testing strategy:
            //
            //   * Reading the cursor *after* the click doesn't work —
            //     NSTextView/STTextView don't move the cursor on ⌘+click,
            //     so `selectedRange()` reports the *old* location.
            //   * Doing my own point-to-offset conversion via
            //     `textView.convert(_:from:)` and `lineFragmentRange(for:)`
            //     gives the wrong coordinate space (textView bounds vs.
            //     content-view interior — see commit history).
            //
            // Use STTextView's public `characterIndex(for screenPoint:)`,
            // which is the official NSTextInputClient hit-tester. It
            // converts screen → window → contentView for us, runs through
            // `textLayoutManager.caretLocation(interactingAt:)`, and
            // returns the document-relative UTF-16 offset (or NSNotFound).
            //
            // Body wrapped in `MainActor.assumeIsolated` because AppKit's
            // Swift overlay marks `NSEvent.window` and the responder
            // hierarchy `@MainActor`. Local monitors fire on the main
            // thread, so the assumption is the documented contract.
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak textView, weak controller] event in
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                // ⌥⌘+click → Open in DB Browser; ⌘+click → Quick View.
                // Require at least ⌘; otherwise the event is unrelated.
                guard flags.contains(.command) else { return event }
                MainActor.assumeIsolated {
                    guard let textView, let controller else { return }
                    // `unsafe` acknowledges SE-0458 — `NSEvent.window` and
                    // `NSResponder.window` are marked `@unsafe` in the
                    // AppKit overlay; we're already main-actor isolated.
                    let eventWindow = event.window
                    guard Coordinator.shouldTrigger(eventWindow: eventWindow,
                                                    locationInWindow: event.locationInWindow,
                                                    textView: textView) else { return }
                    guard let window = unsafe textView.window else { return }
                    let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
                    let offset = textView.characterIndex(for: screenPoint)
                    guard offset != NSNotFound else { return }
                    if flags.contains(.option) {
                        // ⌥⌘+click → Open in DB Browser
                        controller.openInBrowserAtTextLocation(textView: textView, utf16Offset: offset)
                    } else {
                        // ⌘+click (no ⌥) → Quick View
                        controller.triggerAtTextLocation(textView: textView, utf16Offset: offset)
                    }
                }
                return event
            }
        }

        /// Click-gate predicate. Returns true only when `eventWindow` is the
        /// text view's window AND the click hit-tests onto the text view (or
        /// a descendant of it) — `NSEvent.addLocalMonitorForEvents` is
        /// process-global, so without these gates a ⌘-click in the sidebar,
        /// toolbar, or another worksheet's editor would also pop. Extracted
        /// as a static so it's exercised by `QuickViewClickGateTests`
        /// without synthesizing an `NSEvent`.
        static func shouldTrigger(eventWindow: NSWindow?,
                                  locationInWindow: NSPoint,
                                  textView: NSView) -> Bool {
            // `unsafe` acknowledges the AppKit overlay's `@unsafe` marker on
            // `window` accessors. The caller is main-actor isolated.
            guard let textViewWindow = unsafe textView.window,
                  let eventWindow,
                  eventWindow === textViewWindow else {
                return false
            }
            guard let hit = textViewWindow.contentView?.hitTest(locationInWindow) else {
                return false
            }
            return hit === textView || hit.isDescendant(of: textView)
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        /// `isolated deinit` (SE-0371) keeps the cleanup main-actor-bound
        /// so we can read the `monitor` property without `nonisolated(unsafe)`
        /// hatches. The Swift runtime hops to the main executor for the
        /// deinit body if invoked from another isolation domain.
        isolated deinit {
            removeMonitor()
        }

    }

    func tearDown() {
        // STPlugin teardown happens on a different STPlugin instance copy
        // than makeCoordinator, so the coordinator's deinit is what really
        // owns monitor cleanup. Nothing to do here.
    }
}

/// Tiny target object owning the closure invoked when the user picks the
/// "Quick View" context menu item.
@MainActor
private final class QuickViewMenuTarget: NSObject {
    private let action: () -> Void
    init(action: @escaping () -> Void) {
        self.action = action
    }
    @objc func invoke(_ sender: Any?) {
        action()
    }
}
