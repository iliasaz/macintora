//
//  SQLContextAnalyzer.swift
//  Macintora
//
//  Decides what kind of completion to offer at a given cursor position by
//  combining a tree-sitter parse tree with a small backward-tokenizer scan
//  over the raw source. The backward scan keeps suggestions working when the
//  parse tree contains ERROR nodes mid-typing — common while the user is
//  still typing the identifier we're about to complete.
//

import Foundation
import STPluginNeon  // re-exports SwiftTreeSitter

/// Where the cursor sits and what kind of names should be offered.
enum CompletionContext: Equatable, Sendable {
    /// Inside a FROM clause (or right after the FROM keyword) — suggest tables/views.
    case afterFromKeyword(prefix: String)

    /// Inside SELECT/WHERE/JOIN/GROUP BY/ORDER BY/HAVING/CONNECT BY/START WITH —
    /// suggest column names. `qualifier` is nil when the user has not typed
    /// `alias.` (in which case all in-scope columns are candidates).
    case columnReference(qualifier: String?, prefix: String)

    /// User typed `qualifier.partial` somewhere. Resolution order is
    /// alias → table columns, schema → objects (no package members in v1).
    case dottedMember(qualifier: String, prefix: String)

    /// No structural cue; just a bare identifier prefix. Used as a soft
    /// fallback (the data source may still surface relevant tables/objects).
    case identifierPrefix(prefix: String)

    /// Cursor is in a position where completion isn't useful (string literal,
    /// comment, etc.). Caller should suppress the popup.
    case none
}

struct SQLContextAnalyzer {

    /// One-shot analyzer for tests: parses `source` with the Oracle SQL
    /// grammar and runs `analyze(...)` against the resulting tree. Lets the
    /// test target avoid linking SwiftTreeSitter directly.
    static func parseAndAnalyze(_ source: String, utf16Offset: Int) -> CompletionContext {
        let tree = SQLParserHelper.parse(source)
        return SQLContextAnalyzer().analyze(source: source, tree: tree, utf16Offset: utf16Offset)
    }

    /// `source` and `tree` should describe the same buffer; some lag is
    /// acceptable. `utf16Offset` is the cursor location in NSString units.
    func analyze(source: String,
                 tree: SwiftTreeSitter.Tree?,
                 utf16Offset: Int) -> CompletionContext {

        // Backward-scan for the prefix and (optional) dotted qualifier purely
        // on the source string. This works even when the tree is broken at
        // the cursor (ERROR node) — common during typing.
        let scan = SourceScanner.scan(source: source, utf16Offset: utf16Offset)

        if scan.insideStringOrComment {
            return .none
        }

        if let qualifier = scan.qualifier {
            return .dottedMember(qualifier: qualifier, prefix: scan.prefix)
        }

        // Map the cursor to a tree node to detect the enclosing clause.
        // Parser is fed UTF-16 LE, so byte offset = `utf16Offset * 2`. Probe
        // both the cursor byte and the preceding byte; at end-of-source the
        // exact-cursor probe lands on the root, but the previous-byte probe
        // sits inside the last identifier/relation we care about.
        if let tree {
            let cap = source.utf16.count
            let units = max(0, min(utf16Offset, cap))
            let target = UInt32(units * 2)
            var probes: [UInt32] = [target]
            if target >= 2 { probes.append(target - 2) }
            for probe in probes {
                guard let node = tree.rootNode?.descendant(in: probe..<probe),
                      let kind = enclosingClauseKind(of: node) else { continue }
                switch kind {
                case .from:
                    return .afterFromKeyword(prefix: scan.prefix)
                case .columnContext:
                    return .columnReference(qualifier: nil, prefix: scan.prefix)
                }
            }
        }

        // Fallback: incomplete inputs like "SELECT * FROM " don't produce
        // a `from` node yet. Look backward in the source for the most recent
        // SQL clause keyword to decide the context.
        switch lastClauseKeyword(source: source, before: utf16Offset) {
        case "FROM", "UPDATE", "INTO", "JOIN":
            return .afterFromKeyword(prefix: scan.prefix)
        case "WHERE", "AND", "OR", "ON", "BY", "HAVING", "SELECT":
            return .columnReference(qualifier: nil, prefix: scan.prefix)
        default:
            return .identifierPrefix(prefix: scan.prefix)
        }
    }

    /// Walks the source backwards from `cursor` looking for the most recent
    /// SQL clause keyword (FROM/WHERE/...). Used as a fallback when the tree
    /// fails to localise context for incomplete input.
    private func lastClauseKeyword(source: String, before cursor: Int) -> String {
        let utf16 = source.utf16
        let cap = utf16.count
        let safe = max(0, min(cursor, cap))
        // Walk back word by word.
        var i = safe
        while i > 0 {
            // Skip non-letter chars.
            while i > 0 {
                let ch = utf16[utf16.index(utf16.startIndex, offsetBy: i - 1)]
                if let scalar = Unicode.Scalar(ch), scalar.properties.isAlphabetic { break }
                i -= 1
            }
            // Capture the word.
            let end = i
            while i > 0 {
                let ch = utf16[utf16.index(utf16.startIndex, offsetBy: i - 1)]
                guard let scalar = Unicode.Scalar(ch), scalar.properties.isAlphabetic else { break }
                i -= 1
            }
            if i == end { break }
            let startIdx = utf16.index(utf16.startIndex, offsetBy: i)
            let endIdx = utf16.index(utf16.startIndex, offsetBy: end)
            if let start = startIdx.samePosition(in: source),
               let stop = endIdx.samePosition(in: source) {
                let word = source[start..<stop].uppercased()
                let clauseKeywords: Set<String> = [
                    "FROM", "WHERE", "AND", "OR", "JOIN", "ON", "BY",
                    "GROUP", "ORDER", "HAVING", "UPDATE", "INTO", "SELECT"
                ]
                if clauseKeywords.contains(word) {
                    return word
                }
            }
            // Continue backwards from before this word.
        }
        return ""
    }

    // MARK: - Tree walk

    private enum ClauseKind {
        case from
        case columnContext
    }

    /// Walk ancestors looking for a node type that maps to a known clause.
    /// Returns nil when nothing meaningful is found; the caller falls back
    /// to identifier-prefix completion.
    private func enclosingClauseKind(of node: SwiftTreeSitter.Node) -> ClauseKind? {
        var current: SwiftTreeSitter.Node? = node
        while let n = current {
            switch n.nodeType {
            case "from", "relation":
                return .from
            case "where", "join", "cross_join", "lateral_join", "lateral_cross_join",
                 "group_by", "order_by", "having", "select",
                 "start_with_clause", "connect_by_clause":
                return .columnContext
            default:
                current = n.parent
            }
        }
        return nil
    }
}

// MARK: - Source scanner (tree-independent prefix / qualifier extraction)

/// Looks at the raw source around the cursor to extract the identifier prefix
/// the user is currently typing and, if the previous non-whitespace token is
/// a `.`, the qualifier identifier preceding that dot. Tolerates the parse
/// tree being out of date with the most recent keystroke.
struct SourceScanner {
    let prefix: String
    let qualifier: String?
    let insideStringOrComment: Bool

    static func scan(source: String, utf16Offset: Int) -> SourceScanner {
        let ns = source as NSString
        let safeOffset = max(0, min(utf16Offset, ns.length))

        // 1) Walk backward from the cursor while the character is an
        //    identifier character — this is the prefix.
        var prefixStart = safeOffset
        while prefixStart > 0 {
            let prev = ns.character(at: prefixStart - 1)
            guard let scalar = Unicode.Scalar(prev), Self.isIdentifierChar(scalar) else { break }
            prefixStart -= 1
        }
        let prefix = ns.substring(with: NSRange(location: prefixStart, length: safeOffset - prefixStart))

        // 2) If the character immediately before the prefix is a `.`, walk
        //    backward over identifier characters to grab the qualifier.
        var qualifier: String? = nil
        if prefixStart > 0, ns.character(at: prefixStart - 1) == 0x2E /* '.' */ {
            let qualEnd = prefixStart - 1
            var qualStart = qualEnd
            while qualStart > 0 {
                let c = ns.character(at: qualStart - 1)
                guard let scalar = Unicode.Scalar(c), Self.isIdentifierChar(scalar) else { break }
                qualStart -= 1
            }
            if qualStart < qualEnd {
                qualifier = ns.substring(with: NSRange(location: qualStart, length: qualEnd - qualStart))
            }
        }

        // 3) Cheap heuristic: refuse completion inside string literals or
        //    line comments. We scan the current line backward for an
        //    unmatched single-quote or a `--` sequence.
        let lineStart = Self.lineStart(in: ns, before: safeOffset)
        let inString = Self.unmatchedQuote(in: ns, from: lineStart, to: safeOffset)
        let inComment = Self.hasLineCommentMarker(in: ns, from: lineStart, to: safeOffset)

        return SourceScanner(prefix: prefix,
                             qualifier: qualifier,
                             insideStringOrComment: inString || inComment)
    }

    static func isIdentifierChar(_ scalar: Unicode.Scalar) -> Bool {
        // SQL identifiers: letters, digits, underscore, '$', '#'.
        if scalar.isASCII {
            let v = scalar.value
            return (v >= 0x30 && v <= 0x39) ||  // 0-9
                   (v >= 0x41 && v <= 0x5A) ||  // A-Z
                   (v >= 0x61 && v <= 0x7A) ||  // a-z
                   v == 0x5F || v == 0x24 || v == 0x23
        }
        return scalar.properties.isAlphabetic
    }

    private static func lineStart(in ns: NSString, before offset: Int) -> Int {
        var i = offset
        while i > 0 {
            let c = ns.character(at: i - 1)
            if c == 0x0A || c == 0x0D { break }
            i -= 1
        }
        return i
    }

    private static func unmatchedQuote(in ns: NSString, from start: Int, to end: Int) -> Bool {
        var inSingle = false
        var i = start
        while i < end {
            let c = ns.character(at: i)
            if c == 0x27 /* ' */ { inSingle.toggle() }
            i += 1
        }
        return inSingle
    }

    private static func hasLineCommentMarker(in ns: NSString, from start: Int, to end: Int) -> Bool {
        guard end - start >= 2 else { return false }
        var i = start
        while i < end - 1 {
            if ns.character(at: i) == 0x2D /* - */ && ns.character(at: i + 1) == 0x2D {
                return true
            }
            i += 1
        }
        return false
    }
}

