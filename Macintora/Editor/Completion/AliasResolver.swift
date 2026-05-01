//
//  AliasResolver.swift
//  Macintora
//
//  Walks the smallest enclosing query's `from` clause to collect the
//  `[alias: ResolvedTable?]` map needed for column completion when the user
//  types `t.col` against an aliased table reference. Subqueries and other
//  non-table relations resolve to `nil` (no inferred columns in v1).
//

import Foundation
import STPluginNeon  // re-exports SwiftTreeSitter

struct ResolvedTable: Equatable, Sendable {
    let owner: String?
    let name: String
}

struct AliasResolver {

    /// Test-friendly facade: parses `source` and returns the alias map of the
    /// first `from` clause encountered. Avoids exposing tree-sitter types to
    /// the test target.
    static func parseAndResolve(_ source: String) -> [String: ResolvedTable?] {
        let tree = SQLParserHelper.parse(source)
        guard let root = tree.rootNode,
              let fromNode = Self.findFromClause(in: root) else {
            return [:]
        }
        return AliasResolver().aliases(in: fromNode, source: source)
    }

    /// Test-friendly facade exercising the production path: parses `source`,
    /// descends to the node under the cursor at `utf16Offset`, and walks
    /// outward via `aliases(near:source:)`. Use this when the test cares
    /// about the cursor location (e.g. cursor inside the SELECT-list with
    /// FROM as a sibling clause).
    static func parseAndResolve(_ source: String, utf16Offset: Int) -> [String: ResolvedTable?] {
        let tree = SQLParserHelper.parse(source)
        let cap = source.utf16.count
        let units = max(0, min(utf16Offset, cap))
        let target = UInt32(units * 2)
        guard let node = tree.rootNode?.descendant(in: target..<target) else {
            return [:]
        }
        return AliasResolver().aliases(near: node, source: source)
    }

    private static func findFromClause(in node: SwiftTreeSitter.Node) -> SwiftTreeSitter.Node? {
        if node.nodeType == "from" { return node }
        for i in 0..<node.namedChildCount {
            if let child = node.namedChild(at: i),
               let found = findFromClause(in: child) {
                return found
            }
        }
        return nil
    }

    /// Walks up from `node` to the nearest `from` clause and returns the
    /// alias-to-table map. Bare table references are present under their own
    /// upper-cased name (Oracle's default identifier folding) so callers can
    /// look them up uniformly.
    ///
    /// When the tree path can't locate a `from` (e.g. partial typing like
    /// `select b.|` makes the parser fail to recognise the trailing FROM
    /// clause), falls back to a source-text scan scoped to the statement
    /// containing the cursor so column-completion still works mid-typing
    /// without picking up a FROM from a sibling statement in the same
    /// buffer.
    func aliases(near node: SwiftTreeSitter.Node, source: String) -> [String: ResolvedTable?] {
        if let fromNode = enclosingFrom(of: node) {
            let map = aliases(in: fromNode, source: source)
            if !map.isEmpty { return map }
        }
        // node.byteRange is in UTF-16 LE bytes (2 per code unit).
        let cursorUTF16 = Int(node.byteRange.lowerBound) / 2
        return Self.aliasesFromSourceText(source, around: cursorUTF16)
    }

    /// Same as `aliases(near:source:)` but takes the FROM node directly. Useful
    /// for tests.
    func aliases(in fromNode: SwiftTreeSitter.Node, source: String) -> [String: ResolvedTable?] {
        var map: [String: ResolvedTable?] = [:]
        let relations = namedChildren(of: fromNode, ofType: "relation")
        for relation in relations {
            collect(from: relation, source: source, into: &map)
        }
        // FROM may also enclose nested join clauses whose own `relation`
        // children carry additional aliases; recurse.
        for joinKind in ["join", "cross_join", "lateral_join", "lateral_cross_join"] {
            for join in namedChildren(of: fromNode, ofType: joinKind) {
                for relation in namedChildren(of: join, ofType: "relation") {
                    collect(from: relation, source: source, into: &map)
                }
            }
        }
        return map
    }

    // MARK: - Internals

    /// In `tree-sitter-sql-orcl`, `select` and `from` are *siblings* under
    /// the enclosing `statement` — not parent/child. And cursors at
    /// end-of-source after partial typing land on `ERROR` nodes that aren't
    /// inside `statement` at all. We walk up and also recursively search
    /// each ancestor's subtree so we pick up a `from` on the way out
    /// regardless of where the cursor settled.
    ///
    /// We stop at statement-like boundaries so the search doesn't escape to
    /// a sibling statement's FROM in the same buffer (`select 42 from dual;
    /// select * from bills a;` must not resolve `a` against `from dual`).
    private func enclosingFrom(of node: SwiftTreeSitter.Node) -> SwiftTreeSitter.Node? {
        var current: SwiftTreeSitter.Node? = node
        while let n = current {
            if let from = findDescendant(in: n, ofType: "from") {
                return from
            }
            if Self.isQueryBoundary(n.nodeType) {
                return nil
            }
            current = n.parent
        }
        return nil
    }

    /// Node types that mark the boundary of a query block — we don't escape
    /// past these when hunting for a sibling `from` clause.
    private static func isQueryBoundary(_ type: String?) -> Bool {
        switch type {
        case "statement", "subquery", "block", "plsql_block",
             "with", "with_query", "common_table_expression":
            return true
        default:
            return false
        }
    }

    private func findDescendant(in node: SwiftTreeSitter.Node, ofType type: String) -> SwiftTreeSitter.Node? {
        if node.nodeType == type { return node }
        for i in 0..<node.namedChildCount {
            if let child = node.namedChild(at: i),
               let found = findDescendant(in: child, ofType: type) {
                return found
            }
        }
        return nil
    }

    private func collect(from relation: SwiftTreeSitter.Node,
                         source: String,
                         into map: inout [String: ResolvedTable?]) {
        // First named child of `relation` is one of:
        //   subquery | invocation | object_reference | values
        // The optional second is `_alias` (private rule, may not appear in
        // public iteration). We pull the alias by walking the children.
        let table = resolveTable(in: relation, source: source)

        // Locate the alias identifier, if any. The grammar's `_alias` is a
        // hidden rule, so its child identifier appears as a direct child of
        // the relation. Heuristic: the LAST `identifier` child of `relation`
        // that is NOT the table's `name` field is the alias.
        let alias = aliasIdentifier(in: relation, source: source, excluding: table?.name)

        switch (alias, table) {
        case (let aliasName?, let resolved):
            map[aliasName.uppercased()] = resolved
        case (nil, let resolved?):
            // Bare table reference — alias defaults to the table name.
            map[resolved.name.uppercased()] = resolved
        case (nil, nil):
            break
        }
    }

    private func resolveTable(in relation: SwiftTreeSitter.Node, source: String) -> ResolvedTable? {
        guard let firstChild = firstNamedChild(of: relation) else { return nil }
        switch firstChild.nodeType {
        case "object_reference":
            return parseObjectReference(firstChild, source: source)
        case "subquery", "invocation", "values":
            return nil
        default:
            return nil
        }
    }

    private func parseObjectReference(_ node: SwiftTreeSitter.Node, source: String) -> ResolvedTable? {
        // Three valid shapes per grammar/expressions.js:
        //   db.schema.name | schema.name | name
        // The `name` field is always present; `schema` only on the dotted forms.
        let nameNode = node.child(byFieldName: "name")
        let schemaNode = node.child(byFieldName: "schema")
        guard let nameText = nameNode.flatMap({ text(of: $0, in: source) }) else { return nil }
        let owner = schemaNode.flatMap { text(of: $0, in: source)?.uppercased() }
        return ResolvedTable(owner: owner, name: nameText.uppercased())
    }

    private func aliasIdentifier(in relation: SwiftTreeSitter.Node,
                                 source: String,
                                 excluding tableName: String?) -> String? {
        // Walk named children in reverse and pick the first `identifier`
        // whose text differs from the table name. Handles the implicit
        // `_alias` hidden rule case where the alias appears as a sibling of
        // `object_reference`.
        let count = relation.namedChildCount
        for i in stride(from: count - 1, through: 0, by: -1) {
            guard let child = relation.namedChild(at: i) else { continue }
            if child.nodeType == "identifier" {
                if let txt = text(of: child, in: source) {
                    if let tableName, txt.uppercased() == tableName { continue }
                    return txt
                }
            }
        }
        return nil
    }

    private func firstNamedChild(of node: SwiftTreeSitter.Node) -> SwiftTreeSitter.Node? {
        guard node.namedChildCount > 0 else { return nil }
        return node.namedChild(at: 0)
    }

    private func namedChildren(of node: SwiftTreeSitter.Node, ofType type: String) -> [SwiftTreeSitter.Node] {
        var result: [SwiftTreeSitter.Node] = []
        for i in 0..<node.namedChildCount {
            if let child = node.namedChild(at: i), child.nodeType == type {
                result.append(child)
            }
        }
        return result
    }

    /// Source-text fallback used when tree-sitter can't produce a usable
    /// `from` node — typically when partial typing in the SELECT-list
    /// (`SELECT b.|`) confuses the grammar and the trailing FROM never
    /// parses. Looks for the literal `FROM` keyword inside the statement
    /// containing `cursorUTF16` (delimited by `;`) and pulls comma-
    /// separated `[schema.]table [[AS] alias]` specs out until it hits a
    /// terminator (WHERE / GROUP BY / ORDER BY / HAVING / `;`).
    ///
    /// `cursorUTF16` defaults to `.max` for backward compatibility (treat
    /// the entire source as one statement). Doesn't attempt to handle JOIN
    /// syntax — we'd want a real tokeniser for that — but the common case
    /// the editor sees mid-typing is the comma-separated form.
    static func aliasesFromSourceText(_ source: String,
                                      around cursorUTF16: Int = .max) -> [String: ResolvedTable?] {
        let nsSource = source as NSString
        let safeCursor = max(0, min(cursorUTF16, nsSource.length))

        // Statement bounds = last `;` strictly before cursor → next `;` at
        // or after cursor (or end of source).
        let beforeCursor = nsSource.substring(to: safeCursor) as NSString
        let lastSemicolon = beforeCursor.range(of: ";", options: .backwards).location
        let stmtStart = (lastSemicolon == NSNotFound) ? 0 : lastSemicolon + 1

        let afterCursor = nsSource.substring(from: safeCursor) as NSString
        let nextSemicolon = afterCursor.range(of: ";").location
        let stmtEnd = (nextSemicolon == NSNotFound)
            ? nsSource.length
            : safeCursor + nextSemicolon

        guard stmtEnd > stmtStart else { return [:] }
        let stmtRange = NSRange(location: stmtStart, length: stmtEnd - stmtStart)
        let stmt = nsSource.substring(with: stmtRange)

        guard let fromRange = stmt.range(of: "\\bfrom\\b",
                                         options: [.regularExpression, .caseInsensitive]) else {
            return [:]
        }
        let afterFrom = stmt[fromRange.upperBound...]
        let terminator = afterFrom.range(
            of: "\\b(where|group\\s+by|order\\s+by|having|connect\\s+by|start\\s+with)\\b|;",
            options: [.regularExpression, .caseInsensitive])
        let body = terminator.map { afterFrom[..<$0.lowerBound] } ?? afterFrom[...]

        var map: [String: ResolvedTable?] = [:]
        for relation in body.split(separator: ",") {
            let trimmed = relation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            // Tokenise on whitespace; ignore parens / hint blocks for v1.
            let tokens = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard let first = tokens.first else { continue }
            let dotted = first.split(separator: ".")
            let owner: String?
            let name: String
            switch dotted.count {
            case 1:
                owner = nil
                name = String(dotted[0]).uppercased()
            case 2:
                owner = String(dotted[0]).uppercased()
                name = String(dotted[1]).uppercased()
            default:
                // Three-part `db.schema.table` — treat schema as owner.
                owner = String(dotted[1]).uppercased()
                name = String(dotted[2]).uppercased()
            }
            // Find an alias token after the table reference. Skip an
            // optional `AS`. The alias must look like an identifier.
            var aliasName: String? = nil
            for tokenIndex in 1..<tokens.count {
                let token = tokens[tokenIndex]
                if token.lowercased() == "as" { continue }
                let trimmedToken = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;()"))
                if trimmedToken.isEmpty { continue }
                if Self.looksLikeIdentifier(trimmedToken) {
                    aliasName = trimmedToken.uppercased()
                }
                break
            }
            let resolved = ResolvedTable(owner: owner, name: name)
            if let aliasName, aliasName != name {
                map[aliasName] = resolved
            } else {
                map[name] = resolved
            }
        }
        return map
    }

    private static func looksLikeIdentifier(_ s: String) -> Bool {
        guard let first = s.unicodeScalars.first else { return false }
        guard first.properties.isAlphabetic || first == "_" else { return false }
        for scalar in s.unicodeScalars {
            let ok = scalar.properties.isAlphabetic
                || (scalar.value >= 0x30 && scalar.value <= 0x39)
                || scalar == "_" || scalar == "$" || scalar == "#"
            if !ok { return false }
        }
        return true
    }

    /// Returns the substring of `source` covered by the node's byte range.
    /// `Parser.parse(_:)` parses input as UTF-16 LE, so tree byte ranges are
    /// `utf16CodeUnitOffset * 2`. We use `String.UTF16View` to convert back
    /// to a Swift `String.Index` and slice natively.
    private func text(of node: SwiftTreeSitter.Node, in source: String) -> String? {
        let lowerByte = Int(node.byteRange.lowerBound)
        let upperByte = Int(node.byteRange.upperBound)
        guard lowerByte >= 0, lowerByte <= upperByte,
              lowerByte.isMultiple(of: 2), upperByte.isMultiple(of: 2) else { return nil }
        let utf16 = source.utf16
        let lowerUnits = lowerByte / 2
        let upperUnits = upperByte / 2
        guard lowerUnits >= 0, upperUnits <= utf16.count else { return nil }
        guard let startUTF16 = utf16.index(utf16.startIndex, offsetBy: lowerUnits, limitedBy: utf16.endIndex),
              let endUTF16 = utf16.index(utf16.startIndex, offsetBy: upperUnits, limitedBy: utf16.endIndex),
              let start = startUTF16.samePosition(in: source),
              let end = endUTF16.samePosition(in: source) else { return nil }
        return String(source[start..<end])
    }
}
