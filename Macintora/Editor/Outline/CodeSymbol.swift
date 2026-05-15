//
//  CodeSymbol.swift
//  Macintora
//
//  A navigable symbol in a PL/SQL source body — a package member, a standalone
//  procedure/function, or a top-level variable/constant declaration. Produced
//  by `CodeSymbolExtractor` from the bundled tree-sitter grammar and consumed
//  by `CodeOutlineView`. Ranges are stored as UTF-16 code-unit offsets (the
//  unit STTextView/`NSRange` and tree-sitter both speak) so they survive being
//  re-resolved against whatever copy of the source string the editor holds.
//

import SwiftUI

struct CodeSymbol: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable, CaseIterable {
        case procedure
        case function
        case variable
        case constant
        case type        // TYPE … IS RECORD/TABLE/VARRAY/REF CURSOR; also SUBTYPE
        case cursor      // CURSOR … IS …
        case exception   // name EXCEPTION;
        case pragma      // PRAGMA …;

        /// Order the outline groups symbols in (members first, then state).
        static let displayOrder: [Kind] = [
            .procedure, .function, .type, .cursor, .exception,
            .variable, .constant, .pragma,
        ]

        /// Short uppercase tag shown in the row badge.
        var badge: String {
            switch self {
            case .procedure: "PROC"
            case .function:  "FUNC"
            case .variable:  "VAR"
            case .constant:  "CONST"
            case .type:      "TYPE"
            case .cursor:    "CUR"
            case .exception: "EXC"
            case .pragma:    "PRAG"
            }
        }

        /// Plural section title.
        var sectionTitle: String {
            switch self {
            case .procedure: "Procedures"
            case .function:  "Functions"
            case .variable:  "Variables"
            case .constant:  "Constants"
            case .type:      "Types"
            case .cursor:    "Cursors"
            case .exception: "Exceptions"
            case .pragma:    "Pragmas"
            }
        }

        var systemImage: String {
            switch self {
            case .procedure: "curlybraces"
            case .function:  "f.cursive"
            case .variable:  "diamond"
            case .constant:  "lock"
            case .type:      "shippingbox"
            case .cursor:    "tablecells"
            case .exception: "exclamationmark.triangle"
            case .pragma:    "tag"
            }
        }

        /// Tint mirrors the DB-browser object palette (the `--o-*` design
        /// tokens) so a package member here and the same icon in the sidebar
        /// read the same hue.
        var tint: Color {
            switch self {
            case .procedure: Color(red: 0xC9 / 255, green: 0x3A / 255, blue: 0x78 / 255)
            case .function:  Color(red: 0x2D / 255, green: 0x94 / 255, blue: 0x60 / 255)
            case .variable:  .secondary
            case .constant:  Color(red: 0x19 / 255, green: 0x86 / 255, blue: 0x82 / 255)
            case .type:      Color(red: 0x73 / 255, green: 0x5C / 255, blue: 0xB6 / 255)
            case .cursor:    Color(red: 0x2E / 255, green: 0x7A / 255, blue: 0xB8 / 255)
            case .exception: Color(red: 0xC3 / 255, green: 0x5A / 255, blue: 0x1A / 255)
            case .pragma:    .secondary
            }
        }
    }

    /// Stable within a single extraction pass (source order index). Re-parsing
    /// produces a fresh set — callers must not persist these across parses.
    let id: Int
    let name: String
    let kind: Kind
    /// Signature / type hint for the row's trailing text, e.g. `(p_id NUMBER)`,
    /// `→ BOOLEAN`, `CONSTANT NUMBER`. Already whitespace-normalised. `nil` when
    /// there's nothing useful to show.
    let detail: String?
    /// `true` for forward declarations in a package spec (`PROCEDURE p;`), as
    /// opposed to implementations in a body.
    let isDeclaration: Bool
    /// UTF-16 offsets of the identifier — the caret target on navigation.
    let nameRange: Range<Int>
    /// UTF-16 offsets of the whole construct — used to highlight the symbol the
    /// caret currently sits inside.
    let fullRange: Range<Int>
    /// 1-based line of `nameRange.lowerBound`, for display.
    let line: Int
}
