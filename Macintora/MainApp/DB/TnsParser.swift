import Foundation

/// Parses `tnsnames.ora` files into a list of ``TnsEntry``.
///
/// Real-world Oracle TNS files are messy — they include quoted strings that
/// contain `=` and `,` (TLS certificate DNs), `${TNS_ADMIN}` style
/// substitutions, deeply nested `DESCRIPTION_LIST` blocks, and proxy/cert
/// metadata our app ignores. The parser is forgiving:
///
/// 1. Strip line comments (`#` to end of line).
/// 2. Split the file into top-level `ALIAS = (...)` blocks by walking
///    paren-balanced regions. A malformed block doesn't poison its
///    neighbours — failures are isolated to one entry.
/// 3. Parse each block as a tree of `(KEY = …)` nodes. Scalar values may be
///    bare (no `(`/`)`/`=`/whitespace) or double-quoted.
/// 4. Walk the tree to extract the first ADDRESS host/port and the
///    SERVICE_NAME (preferred) or SID from CONNECT_DATA.
///
/// Pure value type; safe to call from any isolation domain.
nonisolated enum TnsParser {
    /// Parse a single Oracle connect descriptor — the `(DESCRIPTION=…)` body
    /// without an `ALIAS =` prefix. Returns `nil` if the input is not a
    /// well-formed descriptor or doesn't carry enough fields to build a
    /// connection.
    ///
    /// The alias on the returned ``TnsEntry`` is `"<descriptor>"` because no
    /// alias is present in the input — callers that need a real name supply
    /// it themselves.
    static func parseDescriptor(_ contents: String) -> TnsEntry? {
        let stripped = stripComments(contents)
        var scanner = Scanner(source: stripped)
        scanner.skipWhitespace()
        guard let node = scanner.readNode() else { return nil }
        return buildEntry(alias: "<descriptor>", root: node)
    }

    static func parse(_ contents: String) -> [TnsEntry] {
        let stripped = stripComments(contents)
        var entries: [TnsEntry] = []
        for (alias, body) in splitTopLevelBlocks(stripped) {
            var scanner = Scanner(source: body)
            scanner.skipWhitespace()
            guard let node = scanner.readNode() else { continue }
            if let entry = buildEntry(alias: alias, root: node) {
                entries.append(entry)
            }
        }
        return entries
    }

    private static func stripComments(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            // `#` inside a quoted string is *not* a comment. Skip past quoted
            // regions before hunting for the comment marker.
            var inQuote = false
            for (offset, ch) in line.enumerated() {
                if ch == "\"" { inQuote.toggle(); continue }
                if ch == "#", !inQuote {
                    let idx = line.index(line.startIndex, offsetBy: offset)
                    return String(line[..<idx])
                }
            }
            return String(line)
        }.joined(separator: "\n")
    }

    /// Walk the source paren-balanced and pull out each top-level
    /// `IDENTIFIER = ( … )` block. Anything outside a balanced block is
    /// ignored, which makes the parser tolerant of stray text or partly
    /// broken entries.
    private static func splitTopLevelBlocks(_ source: String) -> [(String, String)] {
        let chars = Array(source)
        var i = 0
        var blocks: [(String, String)] = []

        while i < chars.count {
            // Skip whitespace and stray characters until we find an identifier.
            while i < chars.count, !isIdentStart(chars[i]) {
                i += 1
            }
            if i >= chars.count { break }

            let aliasStart = i
            while i < chars.count, isIdentChar(chars[i]) {
                i += 1
            }
            let alias = String(chars[aliasStart..<i])

            // Optional whitespace, then `=`.
            while i < chars.count, chars[i].isWhitespace { i += 1 }
            guard i < chars.count, chars[i] == "=" else { continue }
            i += 1
            while i < chars.count, chars[i].isWhitespace { i += 1 }
            guard i < chars.count, chars[i] == "(" else { continue }

            // Walk paren-balanced. Quoted strings count as opaque so an `(`
            // inside `"…"` doesn't unbalance us.
            //
            // Recovery: if a newline followed by `identifier =` shows up while
            // we're still inside an unclosed block, the previous entry was
            // broken. Abandon it and rewind to the start of the next
            // identifier so it isn't lost too.
            let bodyStart = i
            var depth = 0
            var inQuote = false
            var closed = false
            while i < chars.count {
                let ch = chars[i]
                if inQuote {
                    if ch == "\"" { inQuote = false }
                    i += 1
                    continue
                }
                if ch == "\"" { inQuote = true; i += 1; continue }
                if ch == "(" { depth += 1 }
                else if ch == ")" {
                    depth -= 1
                    if depth == 0 {
                        i += 1
                        blocks.append((alias, String(chars[bodyStart..<i])))
                        closed = true
                        break
                    }
                }
                if ch == "\n", depth > 0, looksLikeNewEntry(chars, from: i + 1) {
                    // Next line starts a new entry — bail on the current
                    // (unclosed) one and rewind to the new identifier.
                    i += 1
                    while i < chars.count, chars[i].isWhitespace, chars[i] != "\n" { i += 1 }
                    break
                }
                i += 1
            }
            if !closed {
                // Either we hit EOF unbalanced or aborted via the recovery
                // path. Either way, this alias yields no entry.
                continue
            }
        }
        return blocks
    }

    /// Cheap lookahead: is `chars[start...]` likely the start of a new
    /// `IDENTIFIER = (` block?
    private static func looksLikeNewEntry(_ chars: [Character], from start: Int) -> Bool {
        var i = start
        while i < chars.count, chars[i].isWhitespace, chars[i] != "\n" { i += 1 }
        guard i < chars.count, isIdentStart(chars[i]) else { return false }
        while i < chars.count, isIdentChar(chars[i]) { i += 1 }
        while i < chars.count, chars[i].isWhitespace, chars[i] != "\n" { i += 1 }
        guard i < chars.count, chars[i] == "=" else { return false }
        i += 1
        while i < chars.count, chars[i].isWhitespace, chars[i] != "\n" { i += 1 }
        return i < chars.count && chars[i] == "("
    }

    private static func isIdentStart(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }

    private static func isIdentChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "." || c == "-"
    }

    private static func buildEntry(alias: String, root: Node) -> TnsEntry? {
        var host: String?
        var port: Int?
        var serviceName: String?
        var sid: String?

        func walk(_ node: Node) {
            switch node {
            case .scalar:
                return
            case .group(let key, let children):
                switch key.uppercased() {
                case "ADDRESS":
                    if host == nil {
                        for child in children {
                            if case let .scalar(k, v) = child {
                                switch k.uppercased() {
                                case "HOST": host = v
                                case "PORT": port = Int(v)
                                default: break
                                }
                            } else {
                                walk(child)
                            }
                        }
                    }
                case "CONNECT_DATA":
                    for child in children {
                        if case let .scalar(k, v) = child {
                            switch k.uppercased() {
                            case "SERVICE_NAME": if serviceName == nil { serviceName = v }
                            case "SID": if sid == nil { sid = v }
                            default: break
                            }
                        }
                    }
                default:
                    for child in children { walk(child) }
                }
            }
        }
        walk(root)

        guard let host, let port, serviceName != nil || sid != nil else {
            return nil
        }
        return TnsEntry(alias: alias, host: host, port: port, serviceName: serviceName, sid: sid)
    }
}

// MARK: - Node model

nonisolated private indirect enum Node {
    case scalar(String, String)
    case group(String, [Node])
}

// MARK: - Scanner

nonisolated private struct Scanner {
    let source: [Character]
    var index: Int = 0

    init(source: String) {
        self.source = Array(source)
    }

    var isAtEnd: Bool { index >= source.count }

    mutating func skipWhitespace() {
        while index < source.count, source[index].isWhitespace {
            index += 1
        }
    }

    mutating func skipToNextLine() {
        while index < source.count, source[index] != "\n" {
            index += 1
        }
        if index < source.count { index += 1 }
    }

    mutating func consume(_ char: Character) -> Bool {
        guard index < source.count, source[index] == char else { return false }
        index += 1
        return true
    }

    mutating func readIdentifier() -> String? {
        skipWhitespace()
        let start = index
        while index < source.count {
            let c = source[index]
            if c.isLetter || c.isNumber || c == "_" || c == "." || c == "-" {
                index += 1
            } else {
                break
            }
        }
        guard index > start else { return nil }
        return String(source[start..<index])
    }

    /// Read a scalar value. May be quoted (`"..."`) or bare. Bare values stop
    /// at the next syntactic character (`)`, `(`, newline) — `=` does not
    /// terminate a bare value because real TNS files contain values like
    /// `${TNS_ADMIN}` and `https_proxy_port=80` where `=` may appear inside
    /// substitutions and parens form the boundary instead.
    mutating func readScalarValue() -> String? {
        skipWhitespace()
        guard index < source.count else { return nil }
        if source[index] == "\"" {
            return readQuotedString()
        }
        let start = index
        while index < source.count {
            let c = source[index]
            if c == ")" || c == "(" || c == "\n" || c == "\r" {
                break
            }
            index += 1
        }
        let trimmed = String(source[start..<index]).trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Reads `"…"` returning the content with the quotes stripped. Doesn't
    /// process escapes — Oracle TNS doesn't define any in its quoting rules.
    mutating func readQuotedString() -> String? {
        guard index < source.count, source[index] == "\"" else { return nil }
        index += 1 // opening quote
        let start = index
        while index < source.count, source[index] != "\"" {
            index += 1
        }
        guard index < source.count else { return nil } // unclosed
        let value = String(source[start..<index])
        index += 1 // closing quote
        return value
    }

    /// Read a `(KEY = …)` expression.
    mutating func readNode() -> Node? {
        skipWhitespace()
        guard consume("(") else { return nil }
        skipWhitespace()
        guard let key = readIdentifier() else { return nil }
        skipWhitespace()
        guard consume("=") else { return nil }
        skipWhitespace()

        // Peek: if next non-ws char is `(`, we have a group of children; else a scalar value.
        if index < source.count, source[index] == "(" {
            var children: [Node] = []
            while !isAtEnd {
                skipWhitespace()
                if consume(")") {
                    return .group(key, children)
                }
                guard let child = readNode() else {
                    return nil
                }
                children.append(child)
            }
            return nil
        } else {
            // scalar value (bare or quoted)
            guard let value = readScalarValue() else { return nil }
            skipWhitespace()
            guard consume(")") else { return nil }
            return .scalar(key, value)
        }
    }
}
