//
//  SubstitutionResolver.swift
//  Macintora
//
//  Resolves SQL*Plus substitution variables (`&name` and `&&name`) in a
//  string. Pure logic — no UI, no side effects. Phase 5 wires the results
//  through the runner; Phase 6 handles the dynamic SET DEFINE toggle.
//
//  Substitution rules implemented:
//    - `&NAME` and `&&NAME` (case-insensitive; folded to uppercase in
//      `defines` lookup and reported names).
//    - Optional terminating `.` is consumed: `&owner..t` resolves to
//      `<value>.t`.
//    - Numeric positional refs (`&1`, `&2`) are recognised but treated as
//      ordinary names — they only resolve if `defines["1"]` is provided.
//    - Substitution applies anywhere in the source, including inside string
//      literals (matching SQL*Plus default behaviour). When SET DEFINE OFF
//      is in effect, the caller passes an empty `defines` map *and* skips
//      `resolve` altogether — the resolver itself does not read directives.
//

import Foundation

struct SubstitutionScan: Equatable {
    /// All distinct names referenced (uppercased).
    let names: Set<String>
    /// Subset that uses `&&` — caller persists their resolved values for the
    /// rest of the session.
    let stickyNames: Set<String>
}

struct SubstitutionResult: Equatable {
    let text: String
    let mapping: OffsetMap
    /// Names that had no entry in `defines`. The reference is left verbatim
    /// in `text` so the caller can prompt and re-resolve.
    let missing: Set<String>
}

enum SubstitutionResolver {

    /// Find all `&` / `&&` references in `text`. Used by the consolidated
    /// up-front prompt to gather every variable in a script before execution
    /// starts.
    static func scan(_ text: String) -> SubstitutionScan {
        var names: Set<String> = []
        var sticky: Set<String> = []
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "&" {
                if let ref = readReference(in: text, at: i) {
                    names.insert(ref.name)
                    if ref.isSticky { sticky.insert(ref.name) }
                    i = ref.endIndex
                    continue
                }
            }
            i = text.index(after: i)
        }
        return SubstitutionScan(names: names, stickyNames: sticky)
    }

    /// Replace `&name` / `&&name` with values from `defines`. Unknown names
    /// are left verbatim and recorded in `missing`.
    static func resolve(_ text: String, defines: [String: String]) -> SubstitutionResult {
        var out = ""
        var segments: [OffsetMap.Segment] = []
        var missing: Set<String> = []

        var i = text.startIndex
        var passStart = text.startIndex
        var resolvedOffset = 0
        var originalOffset = 0

        func flushPassthrough(upTo end: String.Index) {
            guard passStart < end else { return }
            let chunk = String(text[passStart..<end])
            let len = chunk.utf16.count
            segments.append(.init(
                kind: .passthrough,
                resolvedRange: resolvedOffset..<(resolvedOffset + len),
                originalRange: originalOffset..<(originalOffset + len)
            ))
            out.append(chunk)
            resolvedOffset += len
            originalOffset += len
            passStart = end
        }

        while i < text.endIndex {
            if text[i] == "&", let ref = readReference(in: text, at: i) {
                flushPassthrough(upTo: i)
                let originalLen = String(text[i..<ref.endIndex]).utf16.count

                if let value = defines[ref.name] {
                    let valueLen = value.utf16.count
                    segments.append(.init(
                        kind: .substitution,
                        resolvedRange: resolvedOffset..<(resolvedOffset + valueLen),
                        originalRange: originalOffset..<(originalOffset + originalLen)
                    ))
                    out.append(value)
                    resolvedOffset += valueLen
                } else {
                    missing.insert(ref.name)
                    let chunk = String(text[i..<ref.endIndex])
                    segments.append(.init(
                        kind: .passthrough,
                        resolvedRange: resolvedOffset..<(resolvedOffset + originalLen),
                        originalRange: originalOffset..<(originalOffset + originalLen)
                    ))
                    out.append(chunk)
                    resolvedOffset += originalLen
                }

                originalOffset += originalLen
                i = ref.endIndex
                passStart = ref.endIndex
                continue
            }
            i = text.index(after: i)
        }
        flushPassthrough(upTo: text.endIndex)

        let mapping = OffsetMap(
            segments: segments.isEmpty
                ? [.init(kind: .passthrough, resolvedRange: 0..<0, originalRange: 0..<0)]
                : segments,
            originalLength: text.utf16.count,
            resolvedLength: out.utf16.count
        )
        return SubstitutionResult(text: out, mapping: mapping, missing: missing)
    }
}

// MARK: - Reference detection

private struct Reference {
    let name: String       // uppercased
    let isSticky: Bool     // &&
    let endIndex: String.Index   // one past the consumed reference (incl. optional trailing `.`)
}

private func readReference(in text: String, at start: String.Index) -> Reference? {
    // Caller ensured text[start] == "&".
    let next = text.index(after: start)
    guard next < text.endIndex else { return nil }

    let isSticky = text[next] == "&"
    let nameStart = isSticky ? text.index(after: next) : next
    guard nameStart < text.endIndex,
          isSubstitutionNameStart(text[nameStart]) else { return nil }

    var nameEnd = nameStart
    while nameEnd < text.endIndex && isSubstitutionNameChar(text[nameEnd]) {
        nameEnd = text.index(after: nameEnd)
    }
    var refEnd = nameEnd
    if refEnd < text.endIndex && text[refEnd] == "." {
        refEnd = text.index(after: refEnd)
    }
    let name = String(text[nameStart..<nameEnd]).uppercased()
    return Reference(name: name, isSticky: isSticky, endIndex: refEnd)
}

private func isSubstitutionNameStart(_ c: Character) -> Bool {
    c.isLetter || c == "_" || c.isNumber
}

private func isSubstitutionNameChar(_ c: Character) -> Bool {
    c.isLetter || c.isNumber || c == "_"
}
