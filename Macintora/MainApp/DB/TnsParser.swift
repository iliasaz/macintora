import Foundation

/// Parses `tnsnames.ora` files into a list of ``TnsEntry``.
///
/// The grammar handles the typical form:
///
/// ```
/// ALIAS =
///   (DESCRIPTION =
///     (ADDRESS = (PROTOCOL = TCP)(HOST = h)(PORT = 1521))
///     (CONNECT_DATA = (SERVICE_NAME = svc))
///   )
/// ```
///
/// Comments start with `#`. Keys are case-insensitive. If multiple `ADDRESS` blocks
/// are present the first is used. `SERVICE_NAME` takes precedence over `SID`.
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
        var scanner = Scanner(source: stripped)
        var entries: [TnsEntry] = []

        while !scanner.isAtEnd {
            scanner.skipWhitespace()
            guard !scanner.isAtEnd else { break }

            guard let alias = scanner.readIdentifier() else {
                scanner.skipToNextLine()
                continue
            }
            scanner.skipWhitespace()
            guard scanner.consume("=") else {
                scanner.skipToNextLine()
                continue
            }
            scanner.skipWhitespace()
            // Top-level alias body is a `(` expression.
            guard let node = scanner.readNode() else {
                continue
            }
            if let entry = buildEntry(alias: alias, root: node) {
                entries.append(entry)
            }
        }
        return entries
    }

    private static func stripComments(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            if let hash = line.firstIndex(of: "#") {
                return String(line[..<hash])
            }
            return String(line)
        }.joined(separator: "\n")
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

    mutating func readScalarValue() -> String? {
        skipWhitespace()
        let start = index
        while index < source.count {
            let c = source[index]
            if c == ")" || c == "(" || c == "=" || c == "\n" || c == "\r" {
                break
            }
            index += 1
        }
        let trimmed = String(source[start..<index]).trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
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
            // scalar value
            guard let value = readScalarValue() else { return nil }
            skipWhitespace()
            guard consume(")") else { return nil }
            return .scalar(key, value)
        }
    }
}
