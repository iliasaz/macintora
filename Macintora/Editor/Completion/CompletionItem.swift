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

struct ProcedureSuggestion: Sendable, Hashable {
    let owner: String
    /// Package name for package members; the standalone proc/func name otherwise.
    let packageName: String
    let procedureName: String
    let overload: String?
    let subprogramId: Int
    /// `"PROCEDURE"` or `"FUNCTION"` — the ALL_PROCEDURES.OBJECT_TYPE of the
    /// parent (PACKAGE for members) is on `parentType`.
    let kind: String
    let parentType: String
    /// Non-nil when the row is a function — read off the `position == 0`
    /// argument row.
    let returnType: String?
}

struct ProcedureArgumentSuggestion: Sendable, Hashable {
    let owner: String
    let packageName: String
    let procedureName: String
    let overload: String?
    let position: Int
    let argumentName: String?
    let dataType: String
    /// `"IN"` / `"OUT"` / `"IN/OUT"`.
    let inOut: String
    let defaulted: Bool
    let defaultValue: String?
}

// MARK: - STCompletionItem implementation

/// Insertion payload for procedure-signature rows. When present, the
/// coordinator inserts `text` at the cursor (no preceding-identifier
/// strip — the user has just typed `(`) and parks the caret at
/// `caretUTF16Offset` so they can start typing the first value.
struct SignatureInsertion: Sendable {
    let text: String
    let caretUTF16Offset: Int
}

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
        case procedure
        case function
        case generic
    }

    let id = UUID()
    let displayText: String      // shown in the popup row
    let insertText: String       // what gets pasted into the editor
    let secondaryText: String?   // dim secondary (owner / data type / etc.)
    let kind: Kind
    /// Non-nil for procedure-signature rows. Drives caret placement after
    /// insertion and signals the row view to allow vertical wrapping.
    let signatureInsertion: SignatureInsertion?

    init(displayText: String,
         insertText: String,
         secondaryText: String?,
         kind: Kind,
         signatureInsertion: SignatureInsertion? = nil) {
        self.displayText = displayText
        self.insertText = insertText
        self.secondaryText = secondaryText
        self.kind = kind
        self.signatureInsertion = signatureInsertion
    }

    // STCompletionItem requires `view`. Built on demand on the main actor.
    var view: NSView {
        MainActor.assumeIsolated { makeView() }
    }

    @MainActor
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
            symbolName: kind.symbolName,
            allowsWrap: signatureInsertion != nil))
    }
}

// MARK: - SwiftUI row

private struct CompletionRowView: View {
    let displayText: String
    let secondaryText: String?
    let symbolName: String
    /// Signature rows can run long (`(in_csp_id in number, val in varchar2,
    /// fmt in varchar2 default null)`) and don't fit the 450pt popup on a
    /// single line. Allow them to wrap; keep regular rows single-line so
    /// the popup stays compact for tables/columns.
    let allowsWrap: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbolName)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color(nsColor: .controlAccentColor))
                .frame(width: 14, alignment: .center)

            Text(displayText)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Color(nsColor: .labelColor))
                .lineLimit(allowsWrap ? nil : 1)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: allowsWrap)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let secondaryText {
                Text(secondaryText)
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, allowsWrap ? 3 : 0)
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
        case .procedure: return "curlybraces"
        case .function: return "f.cursive"
        case .generic: return "circle"
        }
    }
}

// MARK: - Mapping suggestions to STCompletionItem

extension MacintoraCompletionItem {
    // Oracle stores unquoted identifiers in upper-case, which is what the
    // popup shows. The inserted text is lower-cased so user-written SQL
    // stays in the lower-case style the user prefers; quoted identifiers
    // would need a different policy and are out of scope for v1.

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
            insertText: t.name.lowercased(),
            secondaryText: "\(t.owner) · \(t.objectType)",
            kind: kind)
    }

    static func make(from c: ColumnSuggestion) -> MacintoraCompletionItem {
        MacintoraCompletionItem(
            displayText: c.columnName,
            insertText: c.columnName.lowercased(),
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
            insertText: o.name.lowercased(),
            secondaryText: "\(o.owner) · \(o.type)",
            kind: kind)
    }

    static func make(from p: ProcedureSuggestion) -> MacintoraCompletionItem {
        let kind: Kind = p.kind == "FUNCTION" ? .function : .procedure
        var secondary = p.kind
        if let overload = p.overload, !overload.isEmpty {
            secondary += " #\(overload)"
        }
        if let returnType = p.returnType, !returnType.isEmpty {
            secondary += " → \(returnType)"
        }
        return MacintoraCompletionItem(
            displayText: p.procedureName,
            insertText: p.procedureName.lowercased(),
            secondaryText: secondary,
            kind: kind)
    }

    /// Builds a row that shows the call signature of a single overload —
    /// `(in_csp_id in number, ›val in varchar2‹ default null)`. The
    /// procedure name is omitted because the user has already typed it
    /// before the `(` that triggered the popup; repeating it just steals
    /// horizontal space. Lowercase, monospaced, and allowed to wrap so
    /// the full parameter list stays visible in the 450pt popup.
    ///
    /// The argument at `activeArgumentIndex` is wrapped in `›‹` markers
    /// so the user can see which slot they're filling. Out-of-range
    /// indexes (e.g. the user has typed past the last declared arg)
    /// leave the row unmarked rather than highlighting nothing.
    ///
    /// Accepting the row inserts a true named-argument call template
    /// (`in_csp_id => , val => , fmt => )`) and parks the caret at the
    /// first value slot. Rows with zero arguments produce an empty
    /// insertion — the `(` already typed is a complete call.
    static func make(signatureFrom p: ProcedureSuggestion,
                     arguments: [ProcedureArgumentSuggestion],
                     activeArgumentIndex: Int = -1) -> MacintoraCompletionItem {
        let kind: Kind = p.kind == "FUNCTION" ? .function : .procedure
        let formattedArgs = arguments.enumerated().map { offset, arg -> String in
            let rendered = formatArgument(arg)
            return offset == activeArgumentIndex ? "›\(rendered)‹" : rendered
        }.joined(separator: ", ")
        // `lowercased()` is locale-independent and leaves non-letter code
        // points (the `›‹` markers, U+203A / U+2039) untouched.
        let display = "(\(formattedArgs))".lowercased()
        var secondary = p.kind
        if let overload = p.overload, !overload.isEmpty {
            secondary += " #\(overload)"
        }
        if let returnType = p.returnType, !returnType.isEmpty {
            secondary += " → \(returnType)"
        }
        let insertion = makeSignatureInsertion(arguments: arguments)
        return MacintoraCompletionItem(
            displayText: display,
            insertText: insertion?.text ?? "",
            secondaryText: secondary,
            kind: kind,
            signatureInsertion: insertion)
    }

    /// Renders one argument like `name IN VARCHAR2` or `name IN NUMBER
    /// DEFAULT 0`. Anonymous arguments (Oracle ALL_ARGUMENTS allows
    /// nameless positional params for some bind shapes) fall back to the
    /// position number.
    private static func formatArgument(_ arg: ProcedureArgumentSuggestion) -> String {
        let name = arg.argumentName ?? "arg\(arg.position)"
        var rendered = "\(name) \(arg.inOut) \(arg.dataType)"
        if arg.defaulted {
            if let value = arg.defaultValue, !value.isEmpty {
                rendered += " DEFAULT \(value)"
            } else {
                rendered += " DEFAULT"
            }
        }
        return rendered
    }

    /// Produces the named-argument call template inserted when the user
    /// accepts a signature row. Default-valued args are included so the
    /// user sees every named slot up front and can delete the ones they
    /// don't need — matches the "fill all params" behaviour familiar from
    /// IDEs like IntelliJ/Cursor. Caret lands right after the first
    /// `arg => ` (i.e. on the first value position).
    private static func makeSignatureInsertion(
        arguments: [ProcedureArgumentSuggestion]
    ) -> SignatureInsertion? {
        guard !arguments.isEmpty else { return nil }
        let names = arguments.map { ($0.argumentName ?? "arg\($0.position)").lowercased() }
        let firstSlot = "\(names[0]) => "
        let caret = firstSlot.utf16.count
        let restSlots = names.dropFirst().map { "\($0) => " }.joined(separator: ", ")
        let body = restSlots.isEmpty ? firstSlot : "\(firstSlot), \(restSlots)"
        return SignatureInsertion(text: "\(body))", caretUTF16Offset: caret)
    }
}
