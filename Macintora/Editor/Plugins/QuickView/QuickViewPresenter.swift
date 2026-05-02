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
    private var hostingController: NSHostingController<QuickViewContent>?

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

        // Reuse the existing popover when one is up — re-show is cheaper than
        // tearing down and re-creating. Still re-anchors for the new rect.
        if let popover, let hosting = hostingController, popover.isShown {
            hosting.rootView = content
            popover.contentSize = hosting.view.intrinsicContentSize
            close()
        }

        let hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = [.preferredContentSize]
        let popover = NSPopover()
        popover.contentViewController = hosting
        popover.behavior = .transient   // dismiss on click-outside / Esc
        popover.animates = true
        self.popover = popover
        self.hostingController = hosting

        let rect = QuickViewAnchor.rect(for: anchor, in: textView)
        // STTextView's content view is the documentView of an NSScrollView;
        // we anchor relative to the textView itself so the popover follows
        // scrolling correctly until it's dismissed.
        popover.show(relativeTo: rect, of: textView, preferredEdge: .maxY)
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
