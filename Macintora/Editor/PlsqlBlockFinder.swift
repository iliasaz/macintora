//
//  PlsqlBlockFinder.swift
//  Macintora
//
//  Walks the bundled `tree-sitter-sql-orcl` parse tree to locate the outermost
//  top-level anonymous PL/SQL block enclosing the caret. Used by
//  `MainDocumentVM.getCurrentSql` to route `Cmd+R` at a `BEGIN…END;` block to
//  the whole block; non-block contexts fall through to the `;`-splitter.
//

import Foundation
import STPluginNeon  // re-exports SwiftTreeSitter

enum PlsqlBlockFinder {

    /// Returns the source text of the outermost top-level anonymous PL/SQL
    /// block (`plsql_block` whose ancestor chain contains no `CREATE …` /
    /// package-member wrapper) that encloses `cursor` in `text`.
    ///
    /// Returns `nil` when:
    ///   * `cursor` isn't inside any `plsql_block`,
    ///   * the cursor's ancestor chain crosses an `ERROR` node (incomplete
    ///     typing — the parse tree shape isn't trustworthy and the caller
    ///     should fall back to `;`-splitting),
    ///   * or the enclosing block is actually a named subprogram body
    ///     (CREATE PROCEDURE/FUNCTION/PACKAGE BODY/TRIGGER, etc.) — in that
    ///     case `Cmd+R` should compile the DDL, not run a fake anon block.
    ///
    /// The returned text includes the closing `;` after `END`. Any trailing
    /// `/` separator line is excluded — the SQL*Plus directive isn't valid
    /// over Oracle TTC anyway.
    static func anonymousBlockSQL(at cursor: String.Index, in text: String) -> String? {
        guard !text.isEmpty else { return nil }

        let tree = SQLParserHelper.parse(text)
        guard let root = tree.rootNode else { return nil }

        // Parser is fed UTF-16 LE; byte offset = utf16-code-unit offset × 2.
        let cap = text.utf16.count
        let units = max(0, min(cursor.utf16Offset(in: text), cap))
        let byteOffset = UInt32(units * 2)
        guard let leaf = root.descendant(in: byteOffset..<byteOffset) else {
            return nil
        }

        // Walk leaf → root, tracking the outermost enclosing `plsql_block`.
        // Bail on any `ERROR` ancestor — partial typing leaves the tree shape
        // untrustworthy and the caller falls back to `;`-splitting.
        var topmost: SwiftTreeSitter.Node? = nil
        var node: SwiftTreeSitter.Node? = leaf
        while let n = node {
            if n.nodeType == "ERROR" { return nil }
            if n.nodeType == "plsql_block" { topmost = n }
            node = n.parent
        }
        guard let block = topmost else { return nil }

        // Refuse when the block lives inside a named subprogram. A locally
        // declared procedure inside an enclosing anonymous block is fine —
        // the *outer* anonymous block is what we picked as `topmost`, and its
        // own ancestors are clean.
        var above: SwiftTreeSitter.Node? = block.parent
        while let a = above {
            if Self.isSubprogramDefinition(a.nodeType) { return nil }
            above = a.parent
        }

        let lower = Int(block.byteRange.lowerBound) / 2
        var upper = Int(block.byteRange.upperBound) / 2
        guard 0 <= lower, lower <= upper, upper <= cap else { return nil }

        // Some grammar revisions end `plsql_block` at the `END` keyword and
        // leave the trailing `;` as a sibling terminator. Pull the `;` in
        // when it sits right after the node (skipping inline whitespace).
        let utf16 = text.utf16
        while upper < cap {
            let unit = utf16[utf16.index(utf16.startIndex, offsetBy: upper)]
            if unit == 0x20 || unit == 0x09 { upper += 1; continue }   // space / tab
            if unit == 0x3B { upper += 1; break }                      // ';'
            break
        }

        let utf16Lower = utf16.index(utf16.startIndex, offsetBy: lower)
        let utf16Upper = utf16.index(utf16.startIndex, offsetBy: upper)
        guard let sLower = String.Index(utf16Lower, within: text),
              let sUpper = String.Index(utf16Upper, within: text) else {
            return nil
        }
        return String(text[sLower..<sUpper])
    }

    private static func isSubprogramDefinition(_ type: String?) -> Bool {
        switch type {
        case "create_procedure", "create_function",
             "create_package", "create_package_body",
             "create_trigger", "create_type", "create_type_body",
             "package_procedure", "package_function":
            return true
        default:
            return false
        }
    }
}
