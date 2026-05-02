//
//  ObjectAtCursorResolver.swift
//  Macintora
//
//  Maps a cursor offset (UTF-16 NSString units) to a `ResolvedDBReference` —
//  the Quick View feature's input. Walks the tree-sitter parse tree to find
//  the smallest enclosing identifier-bearing node, classifies it, and
//  delegates alias→table mapping to `AliasResolver`.
//
//  The resolver is intentionally a pure function: pass `(offset, source, tree)`
//  in, get a value out. No DB access; the data layer disambiguates between
//  table-vs-view-vs-package-vs-…-vs-synonym via cache lookup.
//

import Foundation
import STPluginNeon  // re-exports SwiftTreeSitter

/// What the Quick View pipeline should look up next. Authored at parse time;
/// the cache fetcher decides between table/view/package/procedure based on
/// what it finds (or doesn't).
enum ResolvedDBReference: Equatable, Sendable {

    /// A 1- or 2-part schema-object name. `owner == nil` means the cursor was
    /// on an unqualified identifier — the fetcher tries the user's default
    /// schema first, then any cached schema. Covers tables, views, packages,
    /// standalone procedures/functions, types, indexes, triggers — the cache
    /// row's `type_` field decides which detail view to render.
    case schemaObject(owner: String?, name: String)

    /// A package-member call (`[owner.]package.member(...)` or `package.member`
    /// outside an invocation context). The fetcher first looks for a package
    /// named `packageName` owning a procedure/function `memberName`. If that
    /// misses, it falls back to treating `(packageOwner, packageName, …)` as
    /// `(schema, standaloneObject)` because two-part names are ambiguous.
    case packageMember(packageOwner: String?, packageName: String, memberName: String)

    /// A column reference. Always carries a concrete table — when the
    /// AliasResolver can't map an alias to a real table, the resolver emits
    /// `.unresolved` instead of guessing.
    case column(tableOwner: String?, tableName: String, columnName: String)

    /// Cursor isn't on something we can resolve (whitespace, punctuation,
    /// inside a string literal or comment, on an unknown alias, etc.).
    case unresolved
}

@MainActor
struct ObjectAtCursorResolver {

    private let aliasResolver = AliasResolver()

    /// Production entry point. Operates on the live parse tree from
    /// `SQLTreeStore`. `tree` may be `nil` (no parse yet); in that case we
    /// fall back to a source-text scan that mirrors `SourceScanner`.
    func resolve(utf16Offset: Int,
                 source: String,
                 tree: SwiftTreeSitter.Tree?) -> ResolvedDBReference {
        // Cheap rejection: cursor in string/comment never resolves.
        let scan = SourceScanner.scan(source: source, utf16Offset: utf16Offset)
        if scan.insideStringOrComment { return .unresolved }

        if let tree {
            if let result = resolveFromTree(tree: tree,
                                            source: source,
                                            utf16Offset: utf16Offset) {
                return result
            }
        }

        // Tree miss: fall back to a source-text-only resolution. Lets Quick
        // View work mid-typing or when the parser has produced an ERROR node
        // around the identifier we care about.
        return resolveFromSourceText(scan: scan,
                                     source: source,
                                     utf16Offset: utf16Offset,
                                     tree: tree)
    }

    /// Test-friendly facade: parses `source` once with `SQLParserHelper` and
    /// resolves at `utf16Offset`. Mirrors `AliasResolver.parseAndResolve(_:utf16Offset:)`.
    static func parseAndResolve(_ source: String, utf16Offset: Int) -> ResolvedDBReference {
        let tree = SQLParserHelper.parse(source)
        return ObjectAtCursorResolver().resolve(utf16Offset: utf16Offset,
                                                source: source,
                                                tree: tree)
    }

    // MARK: - Tree-driven resolution

    /// Walks ancestors from the cursor node looking for an `object_reference`,
    /// `invocation`, or `column_reference`-shaped node. Returns nil when the
    /// tree path doesn't yield anything we can classify (caller falls back to
    /// the source-text scan).
    private func resolveFromTree(tree: SwiftTreeSitter.Tree,
                                 source: String,
                                 utf16Offset: Int) -> ResolvedDBReference? {
        let cap = source.utf16.count
        let units = max(0, min(utf16Offset, cap))
        let target = UInt32(units * 2)

        // Probe the cursor byte and one byte before — at end-of-token the
        // exact-cursor probe lands on the surrounding statement node, but
        // the previous-byte probe sits inside the identifier we want.
        var probes: [UInt32] = [target]
        if target >= 2 { probes.append(target - 2) }

        for probe in probes {
            guard let node = tree.rootNode?.descendant(in: probe..<probe) else { continue }

            // Inside a string/comment? Refuse — the source scanner already
            // checked the line, but the tree gives a more precise answer for
            // multi-line literals.
            if isLiteralOrCommentNode(node) { return .unresolved }

            if let result = classify(node: node, source: source, utf16Offset: utf16Offset) {
                return result
            }
        }
        return nil
    }

    /// Walks `node` upward through ancestors looking for the first classifiable
    /// container. Stops at statement boundaries to avoid escaping into a
    /// sibling statement's syntax.
    private func classify(node: SwiftTreeSitter.Node,
                          source: String,
                          utf16Offset: Int) -> ResolvedDBReference? {
        var current: SwiftTreeSitter.Node? = node
        while let n = current {
            switch n.nodeType {
            case "invocation":
                return classifyInvocation(n, source: source, utf16Offset: utf16Offset)
            case "object_reference":
                return classifyObjectReference(n, source: source, utf16Offset: utf16Offset)
            case "column_reference", "field":
                if let result = classifyColumnReference(n, source: source, utf16Offset: utf16Offset) {
                    return result
                }
                // Structural extraction came up empty — let the source-text
                // fallback in `resolve(...)` try, since the surrounding text
                // typically still has `qualifier.name` we can lex.
                return nil
            case "identifier":
                // Bare identifier. Defer decision — keep walking up to see if
                // a richer parent (object_reference / invocation / column_reference)
                // provides better context. If we hit a query-shaped node first,
                // treat the identifier itself as the reference.
                if let ancestor = n.parent,
                   ["object_reference", "invocation", "column_reference", "field"].contains(ancestor.nodeType ?? "") {
                    current = ancestor
                    continue
                }
                if let raw = text(of: n, in: source) {
                    return classifyBareIdentifier(raw,
                                                  cursorByte: n.byteRange.lowerBound,
                                                  source: source)
                }
                return nil
            default:
                if Self.isQueryBoundary(n.nodeType) { return nil }
                current = n.parent
            }
        }
        return nil
    }

    private func classifyObjectReference(_ node: SwiftTreeSitter.Node,
                                         source: String,
                                         utf16Offset: Int) -> ResolvedDBReference {
        // If this object_reference is the callee of an invocation, the user
        // is on a function/procedure call — defer to the invocation handler
        // so we route to package-member or standalone-procedure semantics.
        if let parent = node.parent, parent.nodeType == "invocation" {
            return classifyInvocation(parent, source: source, utf16Offset: utf16Offset)
        }
        let parts = objectReferenceParts(node, source: source)
        // 2-part `qualifier.name`: if qualifier resolves through the
        // surrounding query's FROM-clause alias map, the user is pointing
        // at a column. Otherwise, fall through to the schema-object path.
        if let qualifier = parts.qualifier, parts.owner == nil {
            let aliases = aliasResolver.aliases(near: node, source: source)
            if let resolved = aliases[qualifier.uppercased()] ?? nil {
                return .column(tableOwner: resolved.owner,
                               tableName: resolved.name,
                               columnName: parts.name.uppercased())
            }
        }
        return referenceFromParts(parts, source: source, cursorByte: node.byteRange.lowerBound)
    }

    private func classifyInvocation(_ node: SwiftTreeSitter.Node,
                                    source: String,
                                    utf16Offset: Int) -> ResolvedDBReference {
        // First named child of `invocation` is the callee — usually an
        // `object_reference`, occasionally a bare `identifier`.
        guard let callee = firstNamedChild(of: node) else { return .unresolved }
        let parts: ObjectParts
        switch callee.nodeType {
        case "object_reference":
            parts = objectReferenceParts(callee, source: source)
        case "identifier":
            guard let name = text(of: callee, in: source) else { return .unresolved }
            parts = ObjectParts(owner: nil, qualifier: nil, name: name)
        default:
            return .unresolved
        }

        // 1-part `f(…)` → schema object lookup (procedure/function/synonym).
        if parts.owner == nil, parts.qualifier == nil {
            return .schemaObject(owner: nil, name: parts.name.uppercased())
        }
        // 2-part `[pkg.]proc(…)` → package member is the most likely interpretation.
        if parts.owner == nil, let qualifier = parts.qualifier {
            return .packageMember(packageOwner: nil,
                                  packageName: qualifier.uppercased(),
                                  memberName: parts.name.uppercased())
        }
        // 3-part `owner.pkg.proc(…)` → owner-qualified package member.
        if let owner = parts.owner, let qualifier = parts.qualifier {
            return .packageMember(packageOwner: owner.uppercased(),
                                  packageName: qualifier.uppercased(),
                                  memberName: parts.name.uppercased())
        }
        return .schemaObject(owner: parts.owner?.uppercased(),
                             name: parts.name.uppercased())
    }

    /// Classifies a `column_reference` / `field` node. Returns nil when the
    /// node's structural fields don't expose a `qualifier.name` shape — the
    /// caller then falls back to a source-text scan (which works mid-typing
    /// and across grammar variants where field names differ).
    private func classifyColumnReference(_ node: SwiftTreeSitter.Node,
                                         source: String,
                                         utf16Offset: Int) -> ResolvedDBReference? {
        let parts = objectReferenceParts(node, source: source)
        guard let qualifier = parts.qualifier ?? parts.owner else {
            return nil
        }
        let column = parts.name
        guard !column.isEmpty else { return nil }
        let aliases = aliasResolver.aliases(near: node, source: source)
        if let resolved = aliases[qualifier.uppercased()] ?? nil {
            return .column(tableOwner: resolved.owner,
                           tableName: resolved.name,
                           columnName: column.uppercased())
        }
        // Unknown qualifier — could still be `schema.column` in a SELECT-list
        // hint we can't disambiguate. Defer to schemaObject so the popover
        // can at least show what the qualifier resolves to.
        return .schemaObject(owner: nil, name: qualifier.uppercased())
    }

    /// 1-part bare identifier with no qualifying parent. Could be:
    ///   * a table/view/package referenced without a qualifier — handle as
    ///     `.schemaObject` and let the cache choose the right kind;
    ///   * a column name whose alias is implicit — handled by the aliases
    ///     lookup; only returned as `.column` when exactly one in-scope table
    ///     would carry it (we do NOT fetch here, so the fetcher resolves the
    ///     ambiguity later via cache + alias map).
    private func classifyBareIdentifier(_ raw: String,
                                        cursorByte: UInt32,
                                        source: String) -> ResolvedDBReference {
        let upper = raw.uppercased()
        // Don't try to be clever with bare identifiers — return them as
        // schema objects; the fetcher's table+package multi-probe is the
        // right place to make the call.
        return .schemaObject(owner: nil, name: upper)
    }

    // MARK: - Source-text fallback

    /// When the parse tree isn't usable at the cursor (typical mid-typing,
    /// ERROR nodes, etc.) but the surrounding text still encodes a usable
    /// identifier. Mirrors `SourceScanner` to extract `[qualifier.]name` and
    /// classifies the result the same way as the tree path.
    private func resolveFromSourceText(scan: SourceScanner,
                                       source: String,
                                       utf16Offset: Int,
                                       tree: SwiftTreeSitter.Tree?) -> ResolvedDBReference {
        // Identifier at cursor: walk both ways from `utf16Offset` to capture
        // the full token, not just the prefix to the cursor. `SourceScanner`
        // gives us only the leading half; mirror it forward.
        let nsSource = source as NSString
        let safeCursor = max(0, min(utf16Offset, nsSource.length))

        var start = safeCursor
        while start > 0 {
            let c = nsSource.character(at: start - 1)
            guard let scalar = Unicode.Scalar(c), SourceScanner.isIdentifierChar(scalar) else { break }
            start -= 1
        }
        var end = safeCursor
        while end < nsSource.length {
            let c = nsSource.character(at: end)
            guard let scalar = Unicode.Scalar(c), SourceScanner.isIdentifierChar(scalar) else { break }
            end += 1
        }
        guard end > start else { return .unresolved }
        let name = nsSource.substring(with: NSRange(location: start, length: end - start))

        // Look back for `qualifier.` immediately preceding the name.
        var qualifier: String? = nil
        if start > 0, nsSource.character(at: start - 1) == 0x2E {
            let qEnd = start - 1
            var qStart = qEnd
            while qStart > 0 {
                let c = nsSource.character(at: qStart - 1)
                guard let scalar = Unicode.Scalar(c), SourceScanner.isIdentifierChar(scalar) else { break }
                qStart -= 1
            }
            if qStart < qEnd {
                qualifier = nsSource.substring(with: NSRange(location: qStart, length: qEnd - qStart))
            }
        }

        // Look back for an outer schema qualifier `owner.qualifier.name`.
        var owner: String? = nil
        if let q = qualifier {
            // Locate the start of the qualifier substring we already pulled.
            // `qualifier.length + 1` (for the dot) gives us a probe before it.
            let qLen = q.utf16.count
            let probe = start - 1 - qLen
            if probe > 0, nsSource.character(at: probe - 1) == 0x2E {
                let oEnd = probe - 1
                var oStart = oEnd
                while oStart > 0 {
                    let c = nsSource.character(at: oStart - 1)
                    guard let scalar = Unicode.Scalar(c), SourceScanner.isIdentifierChar(scalar) else { break }
                    oStart -= 1
                }
                if oStart < oEnd {
                    owner = nsSource.substring(with: NSRange(location: oStart, length: oEnd - oStart))
                }
            }
        }

        // If a qualifier exists, it could be either an alias (resolve via
        // AliasResolver to upgrade to `.column`) or a schema/package.
        if let qualifier {
            // Try alias map first; the source-text fallback inside AliasResolver
            // tolerates a missing tree.
            let aliases: [String: ResolvedTable?]
            if let tree, let cursorNode = tree.rootNode?.descendant(in: UInt32(safeCursor * 2)..<UInt32(safeCursor * 2)) {
                aliases = aliasResolver.aliases(near: cursorNode, source: source)
            } else {
                aliases = AliasResolver.aliasesFromSourceText(source, around: safeCursor)
            }
            if let resolved = aliases[qualifier.uppercased()] ?? nil {
                return .column(tableOwner: resolved.owner,
                               tableName: resolved.name,
                               columnName: name.uppercased())
            }
            // Not an alias — treat as schema-or-package.
            if let owner {
                return .packageMember(packageOwner: owner.uppercased(),
                                      packageName: qualifier.uppercased(),
                                      memberName: name.uppercased())
            }
            return .packageMember(packageOwner: nil,
                                  packageName: qualifier.uppercased(),
                                  memberName: name.uppercased())
        }

        // No qualifier — return the bare identifier as a schema object lookup.
        return .schemaObject(owner: nil, name: name.uppercased())
    }

    // MARK: - Helpers

    private struct ObjectParts {
        let owner: String?
        let qualifier: String?  // for 3-part names: the middle segment
        let name: String

        static var empty: ObjectParts { ObjectParts(owner: nil, qualifier: nil, name: "") }
    }

    /// Pulls 1-, 2-, and 3-part name pieces out of an `object_reference`
    /// node. The grammar exposes `name` always, `schema` for the 2-part form,
    /// and a third unnamed identifier for `db.schema.name`. This helper falls
    /// back to walking children when the named fields aren't present.
    private func objectReferenceParts(_ node: SwiftTreeSitter.Node,
                                      source: String) -> ObjectParts {
        let nameNode = node.child(byFieldName: "name")
        let schemaNode = node.child(byFieldName: "schema")

        if let nameText = nameNode.flatMap({ text(of: $0, in: source) }),
           let schemaNode,
           let schemaText = text(of: schemaNode, in: source) {
            // Could be 2-part (schema.name) or 3-part (db.schema.name). Look
            // for a third sibling identifier that isn't the name or schema.
            let outer = identifierBefore(schema: schemaNode, in: node, source: source)
            return ObjectParts(owner: outer,
                               qualifier: schemaText,
                               name: nameText)
        }
        if let nameText = nameNode.flatMap({ text(of: $0, in: source) }) {
            return ObjectParts(owner: nil, qualifier: nil, name: nameText)
        }
        // Fallback: treat children as positional `[a.][b.]c`.
        var idents: [String] = []
        for i in 0..<node.namedChildCount {
            if let child = node.namedChild(at: i),
               child.nodeType == "identifier",
               let txt = text(of: child, in: source) {
                idents.append(txt)
            }
        }
        switch idents.count {
        case 0: return .empty
        case 1: return ObjectParts(owner: nil, qualifier: nil, name: idents[0])
        case 2: return ObjectParts(owner: nil, qualifier: idents[0], name: idents[1])
        default: return ObjectParts(owner: idents[0],
                                    qualifier: idents[idents.count - 2],
                                    name: idents[idents.count - 1])
        }
    }

    /// For a 3-part `db.schema.name`, returns the leftmost identifier (the
    /// "db" segment). The grammar marks `schema` and `name` via field names
    /// but the outer segment is anonymous, so we fish it out by position.
    private func identifierBefore(schema: SwiftTreeSitter.Node,
                                  in parent: SwiftTreeSitter.Node,
                                  source: String) -> String? {
        for i in 0..<parent.namedChildCount {
            guard let child = parent.namedChild(at: i),
                  child.nodeType == "identifier" else { continue }
            // Stop at the schema's position; whatever came before is the outer.
            if child.byteRange.lowerBound >= schema.byteRange.lowerBound { break }
            if let txt = text(of: child, in: source) { return txt }
        }
        return nil
    }

    private func referenceFromParts(_ parts: ObjectParts,
                                    source: String,
                                    cursorByte: UInt32) -> ResolvedDBReference {
        let nameUpper = parts.name.uppercased()
        guard !nameUpper.isEmpty else { return .unresolved }

        if let qualifier = parts.qualifier {
            // 2-part `qualifier.name`: ambiguous between `schema.object` and
            // `package.member`. Default to schema-object; the fetcher tries
            // package-member as a fallback. This keeps the simple table
            // case (`hr.employees`) cheap.
            return .schemaObject(owner: qualifier.uppercased(), name: nameUpper)
        }
        return .schemaObject(owner: parts.owner?.uppercased(), name: nameUpper)
    }

    private func firstNamedChild(of node: SwiftTreeSitter.Node) -> SwiftTreeSitter.Node? {
        guard node.namedChildCount > 0 else { return nil }
        return node.namedChild(at: 0)
    }

    private func isLiteralOrCommentNode(_ node: SwiftTreeSitter.Node) -> Bool {
        switch node.nodeType {
        case "string", "string_literal", "literal_string",
             "comment", "block_comment", "line_comment":
            return true
        default:
            return false
        }
    }

    private static func isQueryBoundary(_ type: String?) -> Bool {
        switch type {
        case "statement", "subquery", "block", "plsql_block",
             "with", "with_query", "common_table_expression",
             "program", "source_file":
            return true
        default:
            return false
        }
    }

    /// Converts a node's UTF-16-LE byte range to a `String` slice. Mirrors
    /// the helper in `AliasResolver`.
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
