// PlsqlBlockDetector.swift
// Detects PL/SQL anonymous blocks (BEGIN…END; / DECLARE…BEGIN…END;)
// at the cursor position for the Run action (fixes issue #14).

import Foundation

// MARK: - Public API

enum PlsqlBlockDetector {

    /// Returns the outermost PL/SQL anonymous block SQL text that contains
    /// `cursor` in `text`. Any trailing `/` terminator line is NOT included.
    /// Returns `nil` if the cursor is not inside such a block.
    static func plsqlAnonBlockSQL(at cursor: String.Index, in text: String) -> String? {
        let blocks = findAllPlsqlAnonBlocks(in: text)
        let containing = blocks.filter { $0.lowerBound <= cursor && cursor < $0.upperBound }
        // Outermost = earliest start; break ties with largest range (latest end).
        guard let outermost = containing.min(by: { lhs, rhs in
            if lhs.lowerBound != rhs.lowerBound { return lhs.lowerBound < rhs.lowerBound }
            return lhs.upperBound > rhs.upperBound
        }) else { return nil }
        return String(text[outermost])
    }

    /// Returns the ranges of all outermost anonymous PL/SQL blocks found in
    /// `text`. Each range spans from the optional `DECLARE` keyword (or `BEGIN`)
    /// through the `;` of the matching `END`. Trailing `/` lines are excluded.
    static func findAllPlsqlAnonBlocks(in text: String) -> [Range<String.Index>] {
        let tokens = collectBlockTokens(in: text)

        // Pass 1: collect (begin, end) pairs at outermost depth only.
        var pairs: [(beginIdx: Int, endIdx: Int)] = []
        var stack: [Int] = []
        for (idx, token) in tokens.enumerated() {
            switch token.kind {
            case .begin:
                stack.append(idx)
            case .end:
                guard let beginIdx = stack.popLast() else { break }
                if stack.isEmpty {
                    pairs.append((beginIdx: beginIdx, endIdx: idx))
                }
            default:
                break
            }
        }

        // Pass 2: for each pair, find the DECLARE that precedes the BEGIN
        // (scanning backward through any nested subprogram bodies), then build
        // the block range.
        var result: [Range<String.Index>] = []
        for pair in pairs {
            guard let semiPos = findSemicolon(after: tokens[pair.endIdx].range.upperBound,
                                              in: text) else { continue }
            let blockEnd = text.index(after: semiPos)
            let declareIdx = findAssociatedDeclare(before: pair.beginIdx, in: tokens)
            let blockStart = declareIdx.map { tokens[$0].range.lowerBound }
                           ?? tokens[pair.beginIdx].range.lowerBound
            result.append(blockStart..<blockEnd)
        }
        return result
    }
}

// MARK: - Token types (file-private)

private enum BlockTokenKind {
    case begin, end, endControl, declare
}

private struct BlockToken {
    let kind: BlockTokenKind
    let range: Range<String.Index>
}

// MARK: - Tokenizer

/// Walks `text` and returns only the block-structuring keywords:
/// BEGIN, DECLARE, END, END IF, END LOOP, END CASE.
/// Strings, comments, and quoted identifiers are skipped.
private func collectBlockTokens(in text: String) -> [BlockToken] {
    var tokens: [BlockToken] = []
    var i = text.startIndex

    while i < text.endIndex {
        let c = text[i]

        // Line comment: -- … \n
        if c == "-" {
            let next = text.index(after: i)
            if next < text.endIndex, text[next] == "-" {
                while i < text.endIndex, text[i] != "\n" { i = text.index(after: i) }
                continue
            }
        }

        // Block comment: /* … */
        if c == "/" {
            let next = text.index(after: i)
            if next < text.endIndex, text[next] == "*" {
                i = text.index(i, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
                while i < text.endIndex {
                    if text[i] == "*" {
                        let n = text.index(after: i)
                        if n < text.endIndex, text[n] == "/" {
                            i = text.index(i, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
                            break
                        }
                    }
                    i = text.index(after: i)
                }
                continue
            }
        }

        // Single-quoted string: '…' with '' escapes
        if c == "'" {
            i = text.index(after: i)
            while i < text.endIndex {
                if text[i] == "'" {
                    i = text.index(after: i)
                    if i < text.endIndex, text[i] == "'" { i = text.index(after: i); continue }
                    break
                }
                i = text.index(after: i)
            }
            continue
        }

        // Quoted identifier: "…"
        if c == "\"" {
            i = text.index(after: i)
            while i < text.endIndex, text[i] != "\"" { i = text.index(after: i) }
            if i < text.endIndex { i = text.index(after: i) }
            continue
        }

        // Skip non-identifier-starting characters
        if !c.isLetter, c != "_" { i = text.index(after: i); continue }

        // Read identifier
        let wordStart = i
        while i < text.endIndex, text[i].isLetter || text[i].isNumber || text[i] == "_" {
            i = text.index(after: i)
        }
        let wordRange = wordStart..<i
        let word = text[wordRange].uppercased()

        switch word {
        case "BEGIN":
            tokens.append(BlockToken(kind: .begin, range: wordRange))

        case "DECLARE":
            tokens.append(BlockToken(kind: .declare, range: wordRange))

        case "END":
            // Peek at next non-space word to distinguish END IF/LOOP/CASE
            var j = i
            while j < text.endIndex, text[j] == " " || text[j] == "\t" { j = text.index(after: j) }
            let nwStart = j
            while j < text.endIndex, text[j].isLetter { j = text.index(after: j) }
            let nextWord = text[nwStart..<j].uppercased()
            let isControl = nextWord == "IF" || nextWord == "LOOP" || nextWord == "CASE"
            tokens.append(BlockToken(kind: isControl ? .endControl : .end, range: wordRange))

        default:
            break
        }
    }
    return tokens
}

// MARK: - Helpers

/// Scans forward from `start`, skipping whitespace and identifier characters
/// (an optional block label after `END`), and returns the index of the first
/// `;`. Returns `nil` if a non-matching character is encountered first.
private func findSemicolon(after start: String.Index, in text: String) -> String.Index? {
    var i = start
    while i < text.endIndex {
        let c = text[i]
        if c == ";" { return i }
        if c.isWhitespace || c.isLetter || c.isNumber || c == "_" {
            i = text.index(after: i)
        } else {
            return nil
        }
    }
    return nil
}

/// Scans backward from `beginIdx - 1` through `tokens`, looking for a
/// `DECLARE` at nesting depth 0. Depth is maintained by counting:
///   `END` → depth++,  `BEGIN` (at depth > 0) → depth--.
/// If a `BEGIN` at depth 0 is encountered first, returns `nil` (no DECLARE).
private func findAssociatedDeclare(before beginIdx: Int, in tokens: [BlockToken]) -> Int? {
    var bwDepth = 0
    var t = beginIdx - 1
    while t >= 0 {
        switch tokens[t].kind {
        case .end:
            bwDepth += 1
        case .begin:
            if bwDepth > 0 {
                bwDepth -= 1
            } else {
                return nil
            }
        case .declare:
            if bwDepth == 0 { return t }
        case .endControl:
            break
        }
        t -= 1
    }
    return nil
}
