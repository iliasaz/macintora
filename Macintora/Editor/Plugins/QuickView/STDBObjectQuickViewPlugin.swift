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

        context.events.onContextMenu { location, contentManager in
            let menu = NSMenu()
            let item = NSMenuItem(
                title: "Quick View",
                action: nil,
                keyEquivalent: "")
            // Use a local target object so we don't rely on the responder
            // chain finding our action on STTextView.
            let target = QuickViewMenuTarget { [weak controller, weak textView] in
                guard let controller, let textView else { return }
                let utf16Offset = contentManager.offset(
                    from: contentManager.documentRange.location,
                    to: location)
                controller.triggerAtTextLocation(textView: textView,
                                                 utf16Offset: utf16Offset)
            }
            item.target = target
            item.action = #selector(QuickViewMenuTarget.invoke(_:))
            // `NSMenuItem.target` is a weak reference, so we need a strong
            // ref to keep the closure alive until the menu is dismissed.
            // `representedObject` is the canonical strong-ref slot on
            // NSMenuItem — using it avoids an `objc_setAssociatedObject`
            // call that Swift 6's strict-memory-safety mode now flags as
            // unsafe.
            item.representedObject = target
            menu.addItem(item)
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
            // The NSEvent local-monitor closure is declared nonisolated by
            // AppKit but fires on the main thread. The strategy:
            //
            //   1. Pre-filter on `event.modifierFlags` (Sendable) for ⌘.
            //   2. Return `event` so AppKit dispatches the click normally —
            //      the cursor moves to the click point through STTextView's
            //      own hit-testing path, which already knows about content-
            //      view coordinate offsets, line gutters, etc.
            //   3. Schedule a main-actor Task to fire Quick View at the
            //      *new* cursor location, which by definition is the click
            //      target. This avoids re-implementing STTextView's point-
            //      to-offset conversion (an earlier attempt got the
            //      coordinate space wrong because `textView.convert(_:from:)`
            //      is bounds-relative, while `lineFragmentRange(for:inContainerAt:)`
            //      is content-view-relative).
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak textView, weak controller] event in
                guard event.modifierFlags.contains(.command) else { return event }
                guard let textView, let controller else { return event }

                Task { @MainActor in
                    controller.triggerAtCursor(textView: textView)
                }
                return event
            }
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

        /// Hit-tests `point` (in `textView` coordinates) against the layout
        /// manager and returns the UTF-16 offset of the resulting text
        /// location. Returns nil for clicks outside any text run.
        @MainActor
        static func utf16Offset(at point: CGPoint, in textView: STTextView) -> Int? {
            let layoutManager = textView.textLayoutManager
            guard let textContentManager = layoutManager.textContentManager else { return nil }
            let docStart = layoutManager.documentRange.location
            // `lineFragmentRange(for:inContainerAt:)` returns the visible line
            // range; its `textSelectionNavigation.textSelections(...)` lookup
            // produces the click-resolved text location.
            guard let fragmentRange = layoutManager.lineFragmentRange(for: point,
                                                                       inContainerAt: docStart),
                  let location = layoutManager.textSelectionNavigation
                    .textSelections(interactingAt: point,
                                    inContainerAt: fragmentRange.location,
                                    anchors: [],
                                    modifiers: [],
                                    selecting: false,
                                    bounds: layoutManager.usageBoundsForTextContainer)
                    .first?.textRanges.first?.location
            else { return nil }
            return textContentManager.offset(from: docStart, to: location)
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
final class QuickViewMenuTarget: NSObject {
    private let action: () -> Void
    init(action: @escaping () -> Void) {
        self.action = action
    }
    @objc func invoke(_ sender: Any?) {
        action()
    }
}
