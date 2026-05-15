//
//  CodeSymbolExtractor.swift
//  Macintora
//
//  Extracts the navigable PL/SQL symbols — package members, standalone
//  procedure/function, top-level variables & constants — from a source body
//  using the bundled `tree-sitter-sql-orcl` grammar (the same parse that drives
//  syntax highlighting). Pure logic, no UI.
//
//  Coverage is bounded by the grammar's current PL/SQL scope: `TYPE … IS
//  RECORD/TABLE/REF CURSOR`, `SUBTYPE`, `CURSOR … IS`, and `… EXCEPTION;`
//  declarations aren't modelled yet (they land in `ERROR` spans) — they're
//  simply skipped here, and a grammar pass will add them later.
//
//  Tree-sitter is fed UTF-16 LE, so node byte offsets are
//  `utf16-code-unit-offset × 2` — see `range(of:)` / `text(of:)` below and the
//  same conversion in `PlsqlBlockFinder` / `ObjectAtCursorResolver`.
//

import Foundation
import OSLog
import STPluginNeon  // re-exports SwiftTreeSitter
import TreeSitterResource

enum CodeSymbolExtractor {

    private static let log = Logger(subsystem: "com.iliasazonov.macintora", category: "outline")

    /// Symbols defined directly in `source`, in source order. Pass an existing
    /// `tree` to avoid re-parsing; otherwise one is built via `SQLParserHelper`.
    static func symbols(in source: String, tree: SwiftTreeSitter.Tree? = nil) -> [CodeSymbol] {
        guard !source.isEmpty else { return [] }
        guard let root = (tree ?? SQLParserHelper.parse(source)).rootNode else {
            log.debug("symbols: no root for \(source.utf16.count, privacy: .public) utf16 units")
            return []
        }

        let collector = Collector(source: source)
        visitTopLevel(root, with: collector)
        log.debug("""
            symbols: \(collector.symbols.count, privacy: .public) extracted from \
            \(source.utf16.count, privacy: .public) utf16 units; \
            root=\(root.nodeType ?? "?", privacy: .public) hasError=\(root.hasError, privacy: .public)
            """)
        return collector.symbols
    }

    /// Walks `program`'s children, descending through the `statement` wrapper
    /// the grammar puts around top-level DDL. `statement` nesting is shallow in
    /// practice, so the recursion is bounded.
    ///
    /// Also handles the **error-recovery** shape: when the grammar can't parse
    /// the package shell (typically because of constructs it doesn't model yet —
    /// `TYPE … IS RECORD`, `CURSOR … IS …`, `SUBTYPE`, `… EXCEPTION;`),
    /// tree-sitter flattens the body's members into direct children of an
    /// `ERROR` root. Picking them up here means a package whose declarations
    /// confuse the parser still gets its procedures and functions outlined.
    private static func visitTopLevel(_ node: SwiftTreeSitter.Node, with collector: Collector) {
        for index in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: index) else { continue }
            switch child.nodeType {
            case "create_package", "create_package_body":
                collector.collectPackageMembers(of: child)
            case "create_procedure", "create_function":
                collector.collectStandaloneProgram(child)
            case "statement", "block":
                visitTopLevel(child, with: collector)
            // Error-recovery: surfaced as siblings under an `ERROR` root.
            case "package_procedure", "package_function",
                 "plsql_subprogram_declaration", "plsql_declaration",
                 "plsql_type_record", "plsql_type_table", "plsql_type_varray",
                 "plsql_type_ref_cursor", "plsql_subtype_definition",
                 "plsql_cursor_definition", "plsql_exception_declaration",
                 "plsql_pragma":
                collector.handlePackageMember(child)
            default:
                continue   // other statements, comments — nothing to outline
            }
        }
    }

    // MARK: - Collector

    private final class Collector {
        let source: String
        private let lineStarts: [Int]
        private(set) var symbols: [CodeSymbol] = []

        /// The grammar can't parse `TYPE … IS …`, `SUBTYPE …`, `CURSOR … IS …`,
        /// `PRAGMA …` yet; tree-sitter recovers each as a `plsql_declaration`
        /// whose "name" is the leading keyword. Those are noise, not variables —
        /// and these words can't be unquoted identifiers anyway, so dropping any
        /// declaration with one of these names is safe.
        private static let noiseDeclarationNames: Set<String> = ["type", "subtype", "cursor", "pragma"]

        init(source: String) {
            self.source = source
            self.lineStarts = Collector.lineStartOffsets(in: source)
        }

        // MARK: Top-level walks

        /// `create_package` / `create_package_body` — direct member children
        /// only. We deliberately don't descend into `package_procedure` /
        /// `package_function` bodies; their locals aren't part of the package
        /// outline.
        func collectPackageMembers(of package: SwiftTreeSitter.Node) {
            for index in 0..<package.namedChildCount {
                guard let member = package.namedChild(at: index) else { continue }
                handlePackageMember(member)
            }
        }

        /// Dispatches a single package member by node type. Shared between the
        /// well-formed walk (`collectPackageMembers`) and the ERROR-root
        /// recovery walk in `visitTopLevel`.
        func handlePackageMember(_ member: SwiftTreeSitter.Node) {
            switch member.nodeType {
            case "package_procedure":
                add(named: member, kind: .procedure, detail: paramsDetail(of: member), isDeclaration: false)
            case "package_function":
                add(named: member, kind: .function, detail: functionDetail(of: member), isDeclaration: false)
            case "plsql_subprogram_declaration":
                let isFunction = member.child(byFieldName: "return_type") != nil
                    || hasNamedChild(member, ofType: "keyword_function")
                add(named: member,
                    kind: isFunction ? .function : .procedure,
                    detail: isFunction ? functionDetail(of: member) : paramsDetail(of: member),
                    isDeclaration: true)
            case "plsql_declaration":
                addDeclaration(member)
            case "plsql_type_record":
                add(named: member, kind: .type, detail: "RECORD", isDeclaration: false)
            case "plsql_type_table":
                let elem = member.child(byFieldName: "element_type").flatMap(text(of:)).map(normalized)
                add(named: member, kind: .type,
                    detail: elem.map { "TABLE OF \($0)" } ?? "TABLE", isDeclaration: false)
            case "plsql_type_varray":
                let elem = member.child(byFieldName: "element_type").flatMap(text(of:)).map(normalized)
                add(named: member, kind: .type,
                    detail: elem.map { "VARRAY OF \($0)" } ?? "VARRAY", isDeclaration: false)
            case "plsql_type_ref_cursor":
                let returnType = member.child(byFieldName: "return_type").flatMap(text(of:)).map(normalized)
                add(named: member, kind: .type,
                    detail: returnType.map { "REF CURSOR RETURN \($0)" } ?? "REF CURSOR",
                    isDeclaration: false)
            case "plsql_subtype_definition":
                let base = member.child(byFieldName: "base_type").flatMap(text(of:)).map(normalized)
                add(named: member, kind: .type,
                    detail: base.map { "SUBTYPE OF \($0)" } ?? "SUBTYPE", isDeclaration: false)
            case "plsql_cursor_definition":
                add(named: member, kind: .cursor,
                    detail: paramsDetail(of: member), isDeclaration: false)
            case "plsql_exception_declaration":
                add(named: member, kind: .exception, detail: nil, isDeclaration: false)
            case "plsql_pragma":
                // Pragmas don't introduce navigable names of their own (the
                // identifier after PRAGMA is the directive, not a symbol). We
                // still emit it so the user sees what's there.
                add(named: member, kind: .pragma, detail: nil, isDeclaration: false)
            default:
                break
            }
        }

        /// Standalone `CREATE PROCEDURE/FUNCTION` — the program itself plus its
        /// own top-level locals (this is the whole object, so those locals are
        /// the only structure there is to show).
        func collectStandaloneProgram(_ program: SwiftTreeSitter.Node) {
            let isFunction = program.nodeType == "create_function"
            add(named: program,
                kind: isFunction ? .function : .procedure,
                detail: isFunction ? functionDetail(of: program) : paramsDetail(of: program),
                isDeclaration: false)
            for index in 0..<program.namedChildCount {
                guard let child = program.namedChild(at: index),
                      child.nodeType == "plsql_declaration" else { continue }
                addDeclaration(child)
            }
        }

        // MARK: Emitting

        private func addDeclaration(_ node: SwiftTreeSitter.Node) {
            if let nameNode = node.child(byFieldName: "name"),
               let name = text(of: nameNode)?.lowercased(),
               Collector.noiseDeclarationNames.contains(name) {
                return
            }
            let isConstant = hasNamedChild(node, ofType: "keyword_constant")
            let typeText = node.child(byFieldName: "type").flatMap(text(of:)).map(normalized)
            let detail = isConstant ? "CONSTANT \(typeText ?? "")" : typeText
            add(named: node, kind: isConstant ? .constant : .variable, detail: detail, isDeclaration: false)
        }

        /// Emits a symbol for a construct that exposes a `name` field.
        private func add(named node: SwiftTreeSitter.Node, kind: CodeSymbol.Kind,
                         detail: String?, isDeclaration: Bool) {
            guard let nameNode = node.child(byFieldName: "name"),
                  let nameRange = range(of: nameNode),
                  let fullRange = range(of: node) else { return }
            let name = displayName(of: nameNode)
            guard !name.isEmpty else { return }
            let trimmedDetail = detail?.trimmingCharacters(in: .whitespaces)
            symbols.append(CodeSymbol(
                id: symbols.count,
                name: name,
                kind: kind,
                detail: (trimmedDetail?.isEmpty ?? true) ? nil : trimmedDetail,
                isDeclaration: isDeclaration,
                nameRange: nameRange,
                fullRange: fullRange,
                line: lineNumber(forUTF16Offset: nameRange.lowerBound)
            ))
        }

        // MARK: Detail strings

        private func paramsDetail(of node: SwiftTreeSitter.Node) -> String? {
            guard let params = firstNamedChild(node, ofType: "plsql_parameter_list"),
                  let raw = text(of: params) else { return nil }
            return truncated(normalized(raw), to: 72)
        }

        private func functionDetail(of node: SwiftTreeSitter.Node) -> String? {
            let params = firstNamedChild(node, ofType: "plsql_parameter_list")
                .flatMap(text(of:)).map { truncated(normalized($0), to: 48) }
            let returnArrow = node.child(byFieldName: "return_type")
                .flatMap(text(of:)).map { "→ \(normalized($0))" }
            let combined = [params, returnArrow].compactMap { $0 }.joined(separator: " ")
            return combined.isEmpty ? nil : truncated(combined, to: 80)
        }

        // MARK: Names

        /// For an `object_reference` name (`schema.proc`) the display name is the
        /// last identifier component; a bare `identifier` name is itself.
        private func displayName(of nameNode: SwiftTreeSitter.Node) -> String {
            if nameNode.nodeType == "object_reference" {
                for index in stride(from: nameNode.namedChildCount - 1, through: 0, by: -1) {
                    if let component = nameNode.namedChild(at: index),
                       component.nodeType == "identifier",
                       let value = text(of: component) {
                        return normalized(value)
                    }
                }
            }
            return text(of: nameNode).map(normalized) ?? ""
        }

        // MARK: Tree helpers

        private func firstNamedChild(_ node: SwiftTreeSitter.Node, ofType type: String) -> SwiftTreeSitter.Node? {
            for index in 0..<node.namedChildCount {
                if let child = node.namedChild(at: index), child.nodeType == type { return child }
            }
            return nil
        }

        private func hasNamedChild(_ node: SwiftTreeSitter.Node, ofType type: String) -> Bool {
            firstNamedChild(node, ofType: type) != nil
        }

        // MARK: Byte-range → UTF-16 conversions

        /// A node's byte range as UTF-16 code-unit offsets, or `nil` if it
        /// doesn't sit on code-unit boundaries or runs past the source.
        private func range(of node: SwiftTreeSitter.Node) -> Range<Int>? {
            let lowerByte = Int(node.byteRange.lowerBound)
            let upperByte = Int(node.byteRange.upperBound)
            guard lowerByte >= 0, lowerByte <= upperByte,
                  lowerByte.isMultiple(of: 2), upperByte.isMultiple(of: 2) else { return nil }
            let lower = lowerByte / 2
            let upper = upperByte / 2
            guard upper <= source.utf16.count else { return nil }
            return lower..<upper
        }

        private func text(of node: SwiftTreeSitter.Node) -> String? {
            guard let units = range(of: node) else { return nil }
            let utf16 = source.utf16
            guard let lower16 = utf16.index(utf16.startIndex, offsetBy: units.lowerBound, limitedBy: utf16.endIndex),
                  let upper16 = utf16.index(utf16.startIndex, offsetBy: units.upperBound, limitedBy: utf16.endIndex),
                  let lower = lower16.samePosition(in: source),
                  let upper = upper16.samePosition(in: source) else { return nil }
            return String(source[lower..<upper])
        }

        // MARK: Line numbers

        private func lineNumber(forUTF16Offset offset: Int) -> Int {
            // Largest i with lineStarts[i] <= offset; +1 for 1-based.
            var low = 0
            var high = lineStarts.count - 1
            var answer = 0
            while low <= high {
                let mid = (low + high) / 2
                if lineStarts[mid] <= offset { answer = mid; low = mid + 1 } else { high = mid - 1 }
            }
            return answer + 1
        }

        private static func lineStartOffsets(in source: String) -> [Int] {
            var starts = [0]
            var offset = 0
            for unit in source.utf16 {
                offset += 1
                if unit == 0x0A { starts.append(offset) }   // '\n'
            }
            return starts
        }

        // MARK: String tidying

        /// Collapse all internal whitespace/newline runs to single spaces and trim.
        private func normalized(_ string: String) -> String {
            string.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        }

        private func truncated(_ string: String, to limit: Int) -> String {
            string.count <= limit ? string : String(string.prefix(max(0, limit - 1))) + "…"
        }
    }
}
