//
//  CompletionItem.swift
//  Macintora
//
//  Sendable suggestion structs returned by `CompletionDataSource` plus the
//  AppKit row view (`MacintoraCompletionItem`) that the built-in
//  `STCompletionWindowController` renders.
//

import AppKit
import SwiftUI
import STTextView

// MARK: - Sendable suggestion structs

struct TableSuggestion: Sendable, Hashable {
    let owner: String
    let name: String
    /// Raw `ALL_OBJECTS.object_type` from the cache — `"TABLE"`, `"VIEW"`,
    /// `"MATERIALIZED VIEW"`, `"SYNONYM"`, etc. Drives both the popup row's
    /// secondary text and the icon choice.
    let objectType: String
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
        // SwiftUI inside `NSHostingView` handles row sizing/layout cleanly —
        // an earlier raw NSStackView attempt left the stack collapsed at
        // (0,0,0,0) inside the cell because NSTableView's autoresizing
        // contract for plain NSViews didn't propagate to the inner stack.
        // STTextView's own demo (`TextEdit/Mac/CompletionItem.swift`) uses
        // the same NSHostingView pattern.
        NSHostingView(rootView: CompletionRowView(
            displayText: displayText,
            secondaryText: secondaryText,
            symbolName: kind.symbolName))
    }
}

// MARK: - SwiftUI row

private struct CompletionRowView: View {
    let displayText: String
    let secondaryText: String?
    let symbolName: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color(nsColor: .controlAccentColor))
                .frame(width: 14, alignment: .center)

            Text(displayText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Color(nsColor: .labelColor))
                .lineLimit(1)
                .truncationMode(.tail)

            if let secondaryText {
                Text(secondaryText)
                    .font(.callout)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
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
        let kind: Kind
        switch t.objectType {
        case "TABLE": kind = .table
        case "VIEW", "MATERIALIZED VIEW": kind = .view
        case "SYNONYM": kind = .generic
        default: kind = .table
        }
        return MacintoraCompletionItem(
            displayText: t.name,
            insertText: t.name,
            secondaryText: "\(t.owner) · \(t.objectType)",
            kind: kind)
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
