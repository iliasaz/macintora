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
            // `NSMenu.addItem(_:)` doesn't retain the target; stash it on the
            // menu item via objc associated objects so it lives until the
            // menu is dismissed.
            objc_setAssociatedObject(item,
                                     &QuickViewMenuTargetAssocKey,
                                     target,
                                     .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            menu.addItem(item)
            return menu
        }
    }

    func makeCoordinator(context: CoordinatorContext) -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        /// `nonisolated(unsafe)` — the monitor token is read on the main
        /// actor (`installCmdClickMonitor` / `removeMonitor`) but `deinit`
        /// runs in the runtime's chosen isolation, which the type checker
        /// can't statically prove is main. `NSEvent.removeMonitor(_:)` is
        /// thread-safe per AppKit, so calling it from any thread is fine.
        nonisolated(unsafe) private var monitor: Any?

        func installCmdClickMonitor(textView: STTextView,
                                    controller: QuickViewController) {
            // Only one monitor per coordinator instance; tearDown removes it.
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak textView, weak controller] event in
                guard let textView, let controller else { return event }
                guard event.modifierFlags.contains(.command) else { return event }
                guard event.window === textView.window else { return event }

                // Hit-test the click against the text view's content bounds.
                let pointInText = textView.convert(event.locationInWindow, from: nil)
                guard textView.bounds.contains(pointInText) else { return event }

                // Map the text-view-coordinate point to a content-text offset.
                guard let offset = MainActor.assumeIsolated({
                    Self.utf16Offset(at: pointInText, in: textView)
                }) else { return event }

                MainActor.assumeIsolated {
                    controller.triggerAtClick(textView: textView,
                                              point: pointInText,
                                              utf16Offset: offset)
                }

                // Return the event so cursor placement still happens — Quick
                // View is non-destructive and doesn't consume the click.
                return event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        deinit {
            // `NSEvent.removeMonitor` is safe from any thread per AppKit docs.
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
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

/// Associated-object key for `NSMenuItem` → `QuickViewMenuTarget` retention.
nonisolated(unsafe) private var QuickViewMenuTargetAssocKey: UInt8 = 0

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
