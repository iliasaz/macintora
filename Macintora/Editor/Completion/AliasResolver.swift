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
    func aliases(near node: SwiftTreeSitter.Node, source: String) -> [String: ResolvedTable?] {
        guard let fromNode = enclosingFrom(of: node) else { return [:] }
        return aliases(in: fromNode, source: source)
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

    private func enclosingFrom(of node: SwiftTreeSitter.Node) -> SwiftTreeSitter.Node? {
        var current: SwiftTreeSitter.Node? = node
        while let n = current {
            if n.nodeType == "from" { return n }
            current = n.parent
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
