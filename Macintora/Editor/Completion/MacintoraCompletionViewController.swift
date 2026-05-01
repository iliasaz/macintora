//
//  MacintoraCompletionViewController.swift
//  Macintora
//
//  STTextView's stock `STCompletionViewController` ships with two visual
//  defaults that don't fit Macintora's editor look:
//
//  1. `NSVisualEffectView` material `.windowBackground` — flat and a bit
//     heavy. We swap it for `.popover`, which is what the system uses for
//     pop-up menus and looks softer behind the suggestion list.
//
//  2. Selected-row fill `NSColor.highlightColor.withAlphaComponent(1)` —
//     paints a near-white opaque rectangle on light mode (the bug that hid
//     row text earlier — see `CompletionItem.swift`). We replace it with
//     `.selectedContentBackgroundColor`, the standard accent-tinted
//     selection used in Finder, source-list sidebars, etc.
//
//  Wired via the `textViewCompletionViewController(_:)` delegate hook on
//  the editor's `Coordinator`. STTextView still owns the popup window
//  itself (positioning, key handling, dismissal); we only customise the
//  view controller it embeds.
//

import AppKit
import STTextView

final class MacintoraCompletionViewController: STCompletionViewController {

    override func loadView() {
        super.loadView()
        // The base controller adds a single `NSVisualEffectView` as the
        // first subview of `view`. Find it and soften the material.
        if let blur = view.subviews.compactMap({ $0 as? NSVisualEffectView }).first {
            blur.material = .popover
            blur.blendingMode = .behindWindow
        }
    }

    override func tableView(_ tableView: NSTableView,
                            rowViewForRow row: Int) -> NSTableRowView? {
        MacintoraCompletionRowView(
            parentCornerRadius: view.layer?.cornerRadius ?? 8,
            inset: tableView.enclosingScrollView?.contentInsets.top ?? 0)
    }
}

/// Mirrors STTextView's private `STTableRowView` but draws the selection
/// with the system's accent-tinted selection color instead of solid white.
private final class MacintoraCompletionRowView: NSTableRowView {

    private let parentCornerRadius: CGFloat
    private let inset: CGFloat

    init(parentCornerRadius: CGFloat, inset: CGFloat) {
        self.parentCornerRadius = parentCornerRadius * 2
        self.inset = inset
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        let radius = max(0, (parentCornerRadius - inset) / 2)
        let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        context.setFillColor(NSColor.alternateSelectedControlTextColor.cgColor)
        path.fill()
        context.restoreGState()
    }
}
