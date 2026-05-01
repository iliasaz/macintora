//
//  ScriptLexer.swift
//  Macintora
//
//  Splits a SQL*Plus script into ordered command units. Hand-rolled
//  character-stream tokenizer rather than tree-sitter — Neon's grammar is
//  tuned for highlighting and does not model SQL*Plus directives, lone-`/`
//  termination, q-quotes uniformly across delimiter shapes, or `@`/`@@`
//  semantics.
//
//  Phase 0: pure parsing only. Side effects (substitution, execution,
//  directive interpretation) live in later phases.
//

import Foundation

/// One classified region of script source, in original-text order.
struct CommandUnit: Equatable {
    enum Kind: Equatable {
        case sql
        case plsqlBlock
        case sqlplus(SqlPlusDirective)
    }

    let kind: Kind
    /// Range in the *original* (un-substituted) source.
    let originalRange: Range<String.Index>
    /// Executable text — terminator stripped, surrounding whitespace trimmed.
    let text: String
}

struct ScriptUnits: Equatable {
    let units: [CommandUnit]
    let originalText: String
}

enum ScriptLexer {
    static func split(_ source: String) -> ScriptUnits {
        var lexer = LexerState(source: source)
        var units: [CommandUnit] = []
        while !lexer.isAtEnd {
            lexer.skipInterUnitTrivia()
            if lexer.isAtEnd { break }

            if let unit = lexer.readDirectiveAtLineStart() {
                units.append(unit)
                continue
            }

            units.append(lexer.readSqlOrPlsqlUnit())
        }
        return ScriptUnits(units: units, originalText: source)
    }
}

// MARK: - State

private struct LexerState {
    let source: String
    var index: String.Index

    init(source: String) {
        self.source = source
        self.index = source.startIndex
    }

    var isAtEnd: Bool { index >= source.endIndex }

    func char(at i: String.Index) -> Character? {
        guard i < source.endIndex else { return nil }
        return source[i]
    }

    func nextIndex(after i: String.Index, by n: Int = 1) -> String.Index {
        source.index(i, offsetBy: n, limitedBy: source.endIndex) ?? source.endIndex
    }

    mutating func advance() {
        if !isAtEnd { index = source.index(after: index) }
    }

    mutating func advance(by n: Int) {
        index = source.index(index, offsetBy: n, limitedBy: source.endIndex) ?? source.endIndex
    }

    func isAtLineStart(at i: String.Index) -> Bool {
        if i == source.startIndex { return true }
        return source[source.index(before: i)] == "\n"
    }
}

// MARK: - Identifier helpers

private func isIdentChar(_ c: Character) -> Bool {
    c.isLetter || c.isNumber || c == "_" || c == "$" || c == "#"
}

// MARK: - Inter-unit trivia

extension LexerState {
    mutating func skipInterUnitTrivia() {
        while !isAtEnd {
            let c = source[index]
            if c.isWhitespace {
                advance()
                continue
            }
            if c == "-" && char(at: nextIndex(after: index)) == "-" {
                consumeLineComment()
                continue
            }
            if c == "/" && char(at: nextIndex(after: index)) == "*" {
                consumeBlockComment()
                continue
            }
            // Lone `/` line between units (SQL*Plus "execute buffer"; we discard).
            if c == "/" && isAtLineStart(at: index) && lineIsBlank(from: nextIndex(after: index)) {
                consumeRestOfLine()
                continue
            }
            break
        }
    }

    /// Whether the rest of the current line (from `start`) is whitespace until
    /// the next `\n` or EOF.
    func lineIsBlank(from start: String.Index) -> Bool {
        var i = start
        while i < source.endIndex {
            let c = source[i]
            if c == "\n" { return true }
            if !c.isWhitespace { return false }
            i = source.index(after: i)
        }
        return true
    }

    mutating func consumeLineComment() {
        advance() // -
        advance() // -
        while !isAtEnd && source[index] != "\n" { advance() }
        if !isAtEnd { advance() }
    }

    mutating func consumeBlockComment() {
        advance() // /
        advance() // *
        while !isAtEnd {
            if source[index] == "*" && char(at: nextIndex(after: index)) == "/" {
                advance(); advance()
                return
            }
            advance()
        }
    }

    mutating func consumeRestOfLine() {
        while !isAtEnd && source[index] != "\n" { advance() }
        if !isAtEnd { advance() }
    }

    mutating func skipHorizontalWhitespace() {
        while !isAtEnd {
            let c = source[index]
            if c == " " || c == "\t" { advance() } else { break }
        }
    }

    /// Read a contiguous identifier-like word starting at `i` *without*
    /// advancing `index`. Returns "" if the first char is not an ident char.
    func peekWord(from i: String.Index) -> String {
        var j = i
        while j < source.endIndex && isIdentChar(source[j]) {
            j = source.index(after: j)
        }
        return String(source[i..<j])
    }

    func peekWord() -> String { peekWord(from: index) }
}

// MARK: - SQL*Plus directive parsing

extension LexerState {
    mutating func readDirectiveAtLineStart() -> CommandUnit? {
        guard isAtLineStart(at: index) else { return nil }
        guard let firstChar = char(at: index) else { return nil }

        let start = index

        // @file or @@file include
        if firstChar == "@" {
            let doubleAt = char(at: nextIndex(after: index)) == "@"
            advance(by: doubleAt ? 2 : 1)
            skipHorizontalWhitespace()
            let restStart = index
            while !isAtEnd && source[index] != "\n" { advance() }
            let path = source[restStart..<index].trimmingCharacters(in: .whitespaces)
            if !isAtEnd { advance() } // consume \n
            return makeDirectiveUnit(start: start, directive: .include(path: path, doubleAt: doubleAt))
        }

        let word = peekWord()
        let upper = word.uppercased()

        switch upper {
        case "REM", "REMARK":
            advance(by: word.count)
            let body = takeRestOfLineRaw()
            return makeDirectiveUnit(start: start, directive: .remark(text: body.trimmingCharacters(in: .whitespaces)))

        case "PROMPT":
            advance(by: word.count)
            // Per SQL*Plus: PROMPT followed by space then message; trailing newline excluded.
            let body = takeRestOfLineRaw()
            let msg: String = body.first == " " ? String(body.dropFirst()) : body
            return makeDirectiveUnit(start: start, directive: .prompt(message: msg))

        case "DEFINE":
            advance(by: word.count)
            let body = takeRestOfLineRaw()
            return makeDirectiveUnit(start: start, directive: parseDefine(body))

        case "UNDEFINE", "UNDEF":
            advance(by: word.count)
            let body = takeRestOfLineRaw()
            return makeDirectiveUnit(start: start, directive: .undefine(name: body.trimmingCharacters(in: .whitespaces)))

        case "SET":
            advance(by: word.count)
            let body = takeRestOfLineRaw()
            return makeDirectiveUnit(start: start, directive: parseSet(body))

        case "SHOW", "SHO":
            advance(by: word.count)
            skipHorizontalWhitespace()
            let next = peekWord().uppercased()
            if next == "ERRORS" || next == "ERR" {
                advance(by: next.count)
                _ = takeRestOfLineRaw()
                return makeDirectiveUnit(start: start, directive: .showErrors)
            }
            let rest = takeRestOfLineRaw()
            return makeDirectiveUnit(start: start, directive: .unrecognized(text: "SHOW \(next)\(rest)"))

        case "WHENEVER":
            advance(by: word.count)
            let body = takeRestOfLineRaw()
            if let parsed = parseWhenever(body) {
                return makeDirectiveUnit(start: start, directive: parsed)
            }
            return makeDirectiveUnit(start: start, directive: .unrecognized(text: "WHENEVER\(body)"))

        default:
            return nil
        }
    }

    /// Consume from current index through the next newline (newline included).
    /// Returned string excludes the trailing newline.
    mutating func takeRestOfLineRaw() -> String {
        let s = index
        while !isAtEnd && source[index] != "\n" { advance() }
        let result = String(source[s..<index])
        if !isAtEnd { advance() }
        return result
    }

    func makeDirectiveUnit(start: String.Index, directive: SqlPlusDirective) -> CommandUnit {
        let raw = String(source[start..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
        return CommandUnit(kind: .sqlplus(directive), originalRange: start..<index, text: raw)
    }
}

// MARK: - Directive body parsing

private func parseDefine(_ body: String) -> SqlPlusDirective {
    let trimmed = body.trimmingCharacters(in: .whitespaces)
    // `DEFINE name = value` or `DEFINE name=value`. Without `=` it lists the
    // variable; we degrade gracefully to a no-op define with empty value.
    guard let eq = trimmed.firstIndex(of: "=") else {
        if trimmed.isEmpty {
            return .unrecognized(text: "DEFINE")
        }
        return .define(name: trimmed.uppercased(), value: "")
    }
    let nameRaw = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
    var valRaw = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
    // SQL*Plus accepts quoted values. Strip surrounding single or double quotes.
    if (valRaw.hasPrefix("'") && valRaw.hasSuffix("'") && valRaw.count >= 2) ||
       (valRaw.hasPrefix("\"") && valRaw.hasSuffix("\"") && valRaw.count >= 2) {
        valRaw = String(valRaw.dropFirst().dropLast())
    }
    return .define(name: nameRaw.uppercased(), value: String(valRaw))
}

private func parseSet(_ body: String) -> SqlPlusDirective {
    let trimmed = body.trimmingCharacters(in: .whitespaces)
    let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map { String($0) }
    guard let key = parts.first?.uppercased() else {
        return .unrecognized(text: "SET")
    }
    let rest = Array(parts.dropFirst())
    let restJoined = rest.joined(separator: " ")

    switch key {
    case "SERVEROUTPUT", "SERVEROUT":
        guard let v = rest.first?.uppercased() else { return .set(.other(name: key, raw: "")) }
        return .set(.serverOutput(v == "ON" || v == "TRUE" || v == "1"))

    case "ECHO":
        guard let v = rest.first?.uppercased() else { return .set(.other(name: key, raw: "")) }
        return .set(.echo(v == "ON" || v == "TRUE" || v == "1"))

    case "FEEDBACK", "FEED":
        guard let v = rest.first?.uppercased() else { return .set(.other(name: key, raw: "")) }
        switch v {
        case "ON": return .set(.feedback(.on))
        case "OFF": return .set(.feedback(.off))
        default:
            if let n = Int(v) { return .set(.feedback(.rows(n))) }
            return .set(.other(name: key, raw: restJoined))
        }

    case "DEFINE", "DEF":
        guard let v = rest.first else { return .set(.other(name: key, raw: "")) }
        switch v.uppercased() {
        case "ON": return .set(.define(.on))
        case "OFF": return .set(.define(.off))
        default:
            if let first = v.first, v.count == 1 {
                return .set(.define(.prefix(first)))
            }
            return .set(.other(name: key, raw: restJoined))
        }

    default:
        return .set(.other(name: key, raw: restJoined))
    }
}

private func parseWhenever(_ body: String) -> SqlPlusDirective? {
    let trimmed = body.trimmingCharacters(in: .whitespaces)
    let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map { String($0).uppercased() }
    guard parts.count >= 2 else { return nil }

    let condition: WheneverCondition
    switch parts[0] {
    case "SQLERROR": condition = .sqlError
    case "OSERROR":  condition = .osError
    default: return nil
    }

    var rest = Array(parts.dropFirst())
    switch rest.first {
    case "CONTINUE":
        rest = Array(rest.dropFirst())
        let cont: ContinueAction
        switch rest.first {
        case "COMMIT":   cont = .commit
        case "ROLLBACK": cont = .rollback
        case "NONE":     cont = .noAction
        default:         cont = .noAction
        }
        return .whenever(condition, .continue(cont))
    case "EXIT":
        rest = Array(rest.dropFirst())
        var commitOrRollback: CommitAction? = nil
        var exitCode: ExitCode = .failure
        // EXIT [SUCCESS|FAILURE|WARNING|n|SQLCODE] [COMMIT|ROLLBACK]
        if let first = rest.first {
            switch first {
            case "SUCCESS": exitCode = .success; rest.removeFirst()
            case "FAILURE": exitCode = .failure; rest.removeFirst()
            case "WARNING": exitCode = .warning; rest.removeFirst()
            case "SQLCODE": exitCode = .sqlCode; rest.removeFirst()
            default:
                if let n = Int(first) { exitCode = .value(n); rest.removeFirst() }
            }
        }
        if let next = rest.first {
            switch next {
            case "COMMIT":   commitOrRollback = .commit
            case "ROLLBACK": commitOrRollback = .rollback
            default: break
            }
        }
        return .whenever(condition, .exit(exitCode, commitOrRollback: commitOrRollback))
    default:
        return nil
    }
}

// MARK: - SQL / PL-SQL body scanning

extension LexerState {
    mutating func readSqlOrPlsqlUnit() -> CommandUnit {
        let unitStart = index
        let isPlsql = peekIsPlsqlBlockStart()
        var trailingTerminator: TerminatorKind = .none

        var inString = false
        var inQQuote = false
        var qCloser: Character = "\0"

        scan: while !isAtEnd {
            let c = source[index]

            // Comments and quoted identifiers only at top level.
            if !inString && !inQQuote {
                if c == "-" && char(at: nextIndex(after: index)) == "-" {
                    consumeLineComment()
                    continue
                }
                if c == "/" && char(at: nextIndex(after: index)) == "*" {
                    consumeBlockComment()
                    continue
                }
                if c == "\"" {
                    consumeQuotedIdentifier()
                    continue
                }
            }

            if c == "'" {
                if inString {
                    // '' escape stays inside the string.
                    if char(at: nextIndex(after: index)) == "'" {
                        advance(); advance()
                    } else {
                        inString = false
                        advance()
                    }
                    continue
                }
                if inQQuote {
                    advance()
                    continue
                }
                if isQQuoteIntro(at: index) {
                    let delimIdx = nextIndex(after: index)
                    if let delim = char(at: delimIdx) {
                        qCloser = closingQDelim(for: delim)
                        inQQuote = true
                        advance(by: 2) // past `'X` to first content char
                        continue
                    }
                }
                inString = true
                advance()
                continue
            }

            if inQQuote {
                if c == qCloser && char(at: nextIndex(after: index)) == "'" {
                    inQQuote = false
                    advance(by: 2)
                    continue
                }
                advance()
                continue
            }

            if inString {
                advance()
                continue
            }

            // Termination checks (top level).
            // Lone `/` line ends both PL/SQL blocks and plain SQL.
            if c == "/" && isAtLineStart(at: index) && lineIsBlank(from: nextIndex(after: index)) {
                consumeRestOfLine()
                trailingTerminator = .slash
                break scan
            }

            // `;` ends a SQL statement; inside PL/SQL it's part of the body.
            if !isPlsql && c == ";" {
                advance()
                trailingTerminator = .semicolon
                break scan
            }

            advance()
        }

        let raw = String(source[unitStart..<index])
        let cleaned = cleanedBodyText(raw, isPlsql: isPlsql, terminator: trailingTerminator)
        return CommandUnit(
            kind: isPlsql ? .plsqlBlock : .sql,
            originalRange: unitStart..<index,
            text: cleaned
        )
    }

    mutating func consumeQuotedIdentifier() {
        advance() // opening "
        while !isAtEnd {
            let c = source[index]
            if c == "\"" {
                // "" escape
                if char(at: nextIndex(after: index)) == "\"" {
                    advance(); advance()
                    continue
                }
                advance()
                return
            }
            advance()
        }
    }

    func isQQuoteIntro(at i: String.Index) -> Bool {
        guard i > source.startIndex else { return false }
        let p1 = source.index(before: i)
        let c1 = source[p1]
        guard c1 == "q" || c1 == "Q" else { return false }
        // The Q must start a token.
        let qStartsToken: Bool
        if p1 == source.startIndex {
            qStartsToken = true
        } else {
            let p2 = source.index(before: p1)
            let c2 = source[p2]
            if isIdentChar(c2) {
                if (c2 == "n" || c2 == "N") {
                    if p2 == source.startIndex {
                        qStartsToken = true
                    } else {
                        let p3 = source.index(before: p2)
                        qStartsToken = !isIdentChar(source[p3])
                    }
                } else {
                    qStartsToken = false
                }
            } else {
                qStartsToken = true
            }
        }
        guard qStartsToken else { return false }
        // Sanity-check the would-be delimiter.
        let delimIdx = source.index(after: i)
        guard delimIdx < source.endIndex else { return false }
        let delim = source[delimIdx]
        if delim == "'" || delim.isWhitespace { return false }
        return true
    }
}

// MARK: - PL/SQL block detection

extension LexerState {
    func peekIsPlsqlBlockStart() -> Bool {
        var i = skipTriviaForLookahead(from: index)
        let first = peekWord(from: i).uppercased()
        switch first {
        case "BEGIN", "DECLARE":
            return true
        case "CREATE":
            i = source.index(i, offsetBy: first.count, limitedBy: source.endIndex) ?? source.endIndex
            return classifyCreateAsPlsql(from: i)
        default:
            return false
        }
    }

    func skipTriviaForLookahead(from start: String.Index) -> String.Index {
        var i = start
        while i < source.endIndex {
            let c = source[i]
            if c.isWhitespace { i = source.index(after: i); continue }
            if c == "-" && (source.index(after: i) < source.endIndex) && source[source.index(after: i)] == "-" {
                while i < source.endIndex && source[i] != "\n" { i = source.index(after: i) }
                if i < source.endIndex { i = source.index(after: i) }
                continue
            }
            if c == "/" && (source.index(after: i) < source.endIndex) && source[source.index(after: i)] == "*" {
                i = source.index(i, offsetBy: 2, limitedBy: source.endIndex) ?? source.endIndex
                while i < source.endIndex {
                    if source[i] == "*" {
                        let n = source.index(after: i)
                        if n < source.endIndex && source[n] == "/" {
                            i = source.index(i, offsetBy: 2, limitedBy: source.endIndex) ?? source.endIndex
                            break
                        }
                    }
                    i = source.index(after: i)
                }
                continue
            }
            break
        }
        return i
    }

    func classifyCreateAsPlsql(from start: String.Index) -> Bool {
        var i = skipTriviaForLookahead(from: start)
        var word = peekWord(from: i).uppercased()

        if word == "OR" {
            i = advanceBy(word.count, from: i)
            i = skipTriviaForLookahead(from: i)
            word = peekWord(from: i).uppercased()
            if word == "REPLACE" {
                i = advanceBy(word.count, from: i)
                i = skipTriviaForLookahead(from: i)
                word = peekWord(from: i).uppercased()
            }
        }

        while word == "EDITIONABLE" || word == "NONEDITIONABLE" {
            i = advanceBy(word.count, from: i)
            i = skipTriviaForLookahead(from: i)
            word = peekWord(from: i).uppercased()
        }

        switch word {
        case "PROCEDURE", "FUNCTION", "TRIGGER", "PACKAGE", "LIBRARY":
            return true
        case "TYPE":
            i = advanceBy(word.count, from: i)
            i = skipTriviaForLookahead(from: i)
            let next = peekWord(from: i).uppercased()
            return next == "BODY"
        default:
            return false
        }
    }

    func advanceBy(_ n: Int, from i: String.Index) -> String.Index {
        source.index(i, offsetBy: n, limitedBy: source.endIndex) ?? source.endIndex
    }
}

private enum TerminatorKind {
    case none
    case semicolon
    case slash
}

private func cleanedBodyText(_ raw: String, isPlsql: Bool, terminator: TerminatorKind) -> String {
    var s = raw
    // Trim trailing newlines/whitespace first.
    while let last = s.last, last.isWhitespace { s.removeLast() }
    switch terminator {
    case .semicolon:
        if s.hasSuffix(";") { s.removeLast() }
    case .slash:
        if s.hasSuffix("/") { s.removeLast() }
    case .none:
        break
    }
    while let last = s.last, last.isWhitespace { s.removeLast() }
    // For PL/SQL, the inner `;` terminator on `END;` stays.
    _ = isPlsql
    // Trim leading whitespace.
    while let first = s.first, first.isWhitespace { s.removeFirst() }
    return s
}

private func closingQDelim(for c: Character) -> Character {
    switch c {
    case "(": return ")"
    case "[": return "]"
    case "{": return "}"
    case "<": return ">"
    default: return c
    }
}
