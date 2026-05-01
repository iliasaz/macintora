//
//  CompletionItem.swift
//  Macintora
//
//  Sendable suggestion structs returned by `CompletionDataSource` plus the
//  AppKit row view (`MacintoraCompletionItem`) that the built-in
//  `STCompletionWindowController` renders.
//

import AppKit
import STTextView

// MARK: - Sendable suggestion structs

struct TableSuggestion: Sendable, Hashable {
    let owner: String
    let name: String
    let isView: Bool
}

struct ColumnSuggestion: Sendable, Hashable {
    let owner: String
    let tableName: String
    let columnName: String
    let dataType: String
}

struct ObjectSuggestion: Sendable, Hashable {
    let owner: String
    let name: String
    let type: String   // "TABLE" / "VIEW" / "PACKAGE" / "PROCEDURE" / etc.
}

// MARK: - STCompletionItem implementation

/// Single row in the completion popup. Marked `@unchecked Sendable` because
/// the only mutable state is the lazy `view`, and AppKit accesses it solely
/// from the main actor (the popup is main-actor-bound). All other properties
/// are `let`s and trivially Sendable.
final class MacintoraCompletionItem: NSObject, STCompletionItem, @unchecked Sendable {

    enum Kind: Sendable {
        case table
        case view
        case column
        case schema
        case packageObject
        case generic
    }

    let id = UUID()
    let displayText: String      // shown in the popup row
    let insertText: String       // what gets pasted into the editor
    let secondaryText: String?   // dim secondary (owner / data type / etc.)
    let kind: Kind

    init(displayText: String,
         insertText: String,
         secondaryText: String?,
         kind: Kind) {
        self.displayText = displayText
        self.insertText = insertText
        self.secondaryText = secondaryText
        self.kind = kind
    }

    // STCompletionItem requires `view`. Built on demand on the main actor.
    var view: NSView {
        MainActor.assumeIsolated { makeView() }
    }

    private func makeView() -> NSView {
        let container = NSStackView()
        container.orientation = .horizontal
        container.alignment = .centerY
        container.spacing = 6
        container.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: kind.symbolName,
                             accessibilityDescription: kind.symbolName)
        icon.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        icon.contentTintColor = .secondaryLabelColor
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let name = NSTextField(labelWithString: displayText)
        name.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        name.textColor = .labelColor
        name.lineBreakMode = .byTruncatingTail

        container.addArrangedSubview(icon)
        container.addArrangedSubview(name)

        if let secondaryText {
            let detail = NSTextField(labelWithString: secondaryText)
            detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            detail.textColor = .secondaryLabelColor
            detail.lineBreakMode = .byTruncatingTail
            detail.setContentHuggingPriority(.defaultLow, for: .horizontal)
            container.addArrangedSubview(detail)
        }

        return container
    }
}

private extension MacintoraCompletionItem.Kind {
    var symbolName: String {
        switch self {
        case .table: return "tablecells"
        case .view: return "rectangle.stack"
        case .column: return "list.bullet"
        case .schema: return "person.crop.square"
        case .packageObject: return "shippingbox"
        case .generic: return "circle"
        }
    }
}

// MARK: - Mapping suggestions to STCompletionItem

extension MacintoraCompletionItem {
    static func make(from t: TableSuggestion) -> MacintoraCompletionItem {
        MacintoraCompletionItem(
            displayText: t.name,
            insertText: t.name,
            secondaryText: t.owner,
            kind: t.isView ? .view : .table)
    }

    static func make(from c: ColumnSuggestion) -> MacintoraCompletionItem {
        MacintoraCompletionItem(
            displayText: c.columnName,
            insertText: c.columnName,
            secondaryText: c.dataType,
            kind: .column)
    }

    static func make(from o: ObjectSuggestion) -> MacintoraCompletionItem {
        let kind: Kind
        switch o.type {
        case "TABLE": kind = .table
        case "VIEW": kind = .view
        case "PACKAGE", "PACKAGE BODY": kind = .packageObject
        default: kind = .generic
        }
        return MacintoraCompletionItem(
            displayText: o.name,
            insertText: o.name,
            secondaryText: "\(o.owner) · \(o.type)",
            kind: kind)
    }
}
