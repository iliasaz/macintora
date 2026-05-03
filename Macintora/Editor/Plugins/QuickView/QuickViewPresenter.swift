//
//  QuickViewPresenter.swift
//  Macintora
//
//  Owns the `NSPopover` + `NSHostingController` lifecycle for Quick View.
//  Anchors the popover at a token's bounding rect (computed from a UTF-16
//  range) or at a click point. Idempotent: presenting a new payload while a
//  popover is already showing closes the previous one and re-anchors.
//
//  Anchor-rect math is in `QuickViewAnchor.swift` rather than the presenter
//  so the conversion can be unit-tested independently.
//

import AppKit
import SwiftUI
import STTextView
import STTextKitPlus

@MainActor
final class QuickViewPresenter: NSObject {

    /// Hostable shape of the rect we want the popover to point at.
    enum Anchor: Equatable {
        /// A UTF-16 range in the editor's content. The presenter resolves it
        /// to a screen-space rect via `STTextView.textLayoutManager`.
        case range(NSRange)

        /// A point in the text view's content-view coordinates (typically
        /// from a Cmd+Click). The popover anchors at a 1×1 rect there.
        case point(CGPoint)
    }

    private weak var textView: STTextView?
    private var popover: NSPopover?
    private var hostingController: QuickViewHostingController?

    init(textView: STTextView) {
        self.textView = textView
    }

    /// Replaces any visible popover with one rendering `payload`. Caller is
    /// expected to invoke this on the main actor.
    func present(payload: QuickViewPayload,
                 anchor: Anchor,
                 openInBrowserAction: (() -> Void)?) {
        guard let textView else { return }

        let content = QuickViewContent(payload: payload,
                                       openInBrowserAction: openInBrowserAction)

        // Always rebuild on present. Re-using the popover would mean keeping
        // the previous anchor rect in sync with the new payload's range, and
        // tearing down a transient `NSPopover` is cheap. Tear down any
        // currently-visible popover so only one Quick View is on screen at a
        // time.
        if popover != nil { close() }

        let hosting = QuickViewHostingController(rootView: content)
        hosting.sizingOptions = [.preferredContentSize]
        let popover = NSPopover()
        popover.contentViewController = hosting
        popover.behavior = .transient   // dismiss on click-outside / Esc
        popover.animates = true
        hosting.popover = popover
        self.popover = popover
        self.hostingController = hosting

        let rect = QuickViewAnchor.rect(for: anchor, in: textView)
        // STTextView's content view is the documentView of an NSScrollView;
        // we anchor relative to the textView itself so the popover follows
        // scrolling correctly until it's dismissed.
        popover.show(relativeTo: rect, of: textView, preferredEdge: .maxY)

        // Make the hosting view the popover window's first responder so
        // Esc reaches our `cancelOperation` override below — without this,
        // a popover whose SwiftUI tree has no interactive elements (the
        // "not cached" placeholder before issue #13 wires the Open in
        // Browser button) leaves no responder for AppKit to deliver Esc
        // to, and the only way to dismiss is click-outside.
        // `unsafe` acknowledges SE-0458 — `NSWindow.makeFirstResponder`
        // is annotated `@unsafe` in the AppKit overlay; we're already
        // on the main actor, so the call is safe in practice.
        unsafe hosting.view.window?.makeFirstResponder(hosting)
    }

    func close() {
        popover?.close()
        popover = nil
        hostingController = nil
    }

    var isVisible: Bool {
        popover?.isShown ?? false
    }
}

/// `NSHostingController` subclass that closes its popover on Esc.
///
/// `NSPopover.behavior == .transient` already dismisses on click-outside,
/// but Esc handling depends on the popover window having a first responder
/// in the responder chain that responds to `cancelOperation(_:)`. SwiftUI's
/// hosting view chains responder through interactive subviews (Lists,
/// Buttons), so payloads with rich content dismiss correctly. The "not
/// cached" / "unknown object" placeholders have no interactive elements
/// today; without this subclass they trapped Esc and required a mouse
/// click to dismiss.
@MainActor
final class QuickViewHostingController: NSHostingController<QuickViewContent> {
    weak var popover: NSPopover?

    override var acceptsFirstResponder: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        popover?.close()
    }
}

// MARK: - Anchor rect math

@MainActor
enum QuickViewAnchor {
    /// Resolves a presenter `Anchor` into a rect in `textView`'s coordinate
    /// space, suitable for `NSPopover.show(relativeTo:of:preferredEdge:)`.
    /// Falls back to a small rect at the cursor when the requested range
    /// can't be located (e.g. it's been clipped out of view).
    static func rect(for anchor: QuickViewPresenter.Anchor,
                     in textView: STTextView) -> NSRect {
        switch anchor {
        case .range(let nsRange):
            return rectForRange(nsRange, in: textView) ?? fallbackRect(in: textView)
        case .point(let point):
            // Convert from the click's content-view coordinates to the text
            // view's coordinate system. The hit-test point we receive is
            // already in the text view's coordinates, so just inflate to a
            // 1×1 rect at that point.
            return NSRect(x: point.x, y: point.y, width: 1, height: 1)
        }
    }

    private static func rectForRange(_ nsRange: NSRange, in textView: STTextView) -> NSRect? {
        guard nsRange.length > 0 else { return nil }
        let layoutManager = textView.textLayoutManager
        guard let textContentManager = layoutManager.textContentManager else { return nil }
        let docStart = textContentManager.documentRange.location
        guard let start = textContentManager.location(docStart, offsetBy: nsRange.location),
              let end = textContentManager.location(docStart,
                                                    offsetBy: nsRange.location + nsRange.length),
              let textRange = NSTextRange(location: start, end: end) else { return nil }
        var union: NSRect = .null
        layoutManager.enumerateTextSegments(in: textRange,
                                            type: .standard,
                                            options: .middleFragmentsExcluded) { _, rect, _, _ in
            if union.isNull { union = rect } else { union = union.union(rect) }
            return true
        }
        if union.isNull { return nil }
        return union
    }

    private static func fallbackRect(in textView: STTextView) -> NSRect {
        // Cursor selection rect, or the visible top-left as a last resort.
        let layoutManager = textView.textLayoutManager
        if let selection = layoutManager.textSelections.first?.textRanges.first,
           let frame = layoutManager.textSegmentFrame(in: selection, type: .standard) {
            return frame
        }
        let visible = textView.visibleRect
        return NSRect(x: visible.minX + 8, y: visible.minY + 8, width: 1, height: 1)
    }
}
