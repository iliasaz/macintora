//
//  MacintoraSTTextView.swift
//  Macintora
//
//  Macintora-specific `STTextView` subclass. Hosts behavioral overrides that
//  diverge from the upstream defaults — currently the Tab/Shift+Tab handling
//  for line indent/outdent. Future Macintora-only editor tweaks should land
//  here too rather than in the SwiftUI wrapper.
//

import AppKit
import STTextView

final class MacintoraSTTextView: STTextView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // SQL editor: keep AppKit's spell/grammar/text-replacement machinery
        // out of the way. NSSpellChecker hops to a default-QoS thread for NLP
        // and surfaces as a "Hang Risk: priority inversion" diagnostic when
        // the user-interactive main thread waits on it. The four `lazy var`s
        // below otherwise default-initialize through NSSpellChecker, which is
        // the priority-inversion path — assigning before any read short-circuits
        // the lazy initializer.
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func insertTab(_ sender: Any?) {
        let selection = textSelection
        guard selection.length > 0 else {
            super.insertTab(sender)
            return
        }
        indentLines(touching: selection)
    }

    override func insertBacktab(_ sender: Any?) {
        outdentLines(touching: textSelection)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .command, event.charactersIgnoringModifiers == "/" {
            toggleLineComment(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Toggle SQL line comments (`-- `) on every line touched by the current
    /// selection. Behavior matches Xcode/VS Code: if every non-blank affected
    /// line is already commented, all are uncommented; otherwise every
    /// non-blank affected line gets a `-- ` prefix at its first non-whitespace
    /// column. Blank/whitespace-only lines are left alone so toggling doesn't
    /// dirty empty lines in diffs.
    @objc func toggleLineComment(_ sender: Any?) {
        let selection = textSelection
        let lineRanges = affectedLineRanges(for: selection)
        guard !lineRanges.isEmpty else { return }
        let fullText = (text ?? "") as NSString
        let marker = "--"
        let prefix = "-- "

        var nonBlank: [(line: NSRange, contentStart: Int)] = []
        for line in lineRanges {
            guard line.length > 0 else { continue }
            let lineEnd = line.location + line.length
            var i = line.location
            var contentStart: Int?
            while i < lineEnd {
                let ch = fullText.substring(with: NSRange(location: i, length: 1))
                if ch == "\n" || ch == "\r" { break }
                if ch != " " && ch != "\t" { contentStart = i; break }
                i += 1
            }
            if let cs = contentStart { nonBlank.append((line, cs)) }
        }
        guard !nonBlank.isEmpty else { return }

        let allCommented = nonBlank.allSatisfy { entry in
            let lineEnd = entry.line.location + entry.line.length
            guard entry.contentStart + 2 <= lineEnd else { return false }
            return fullText.substring(with: NSRange(location: entry.contentStart, length: 2)) == marker
        }

        // (range to replace, replacement) pairs in document order.
        var edits: [(range: NSRange, replacement: String)] = []
        if allCommented {
            for entry in nonBlank {
                let lineEnd = entry.line.location + entry.line.length
                var removeLen = 2
                if entry.contentStart + removeLen < lineEnd,
                   fullText.substring(with: NSRange(location: entry.contentStart + removeLen,
                                                    length: 1)) == " " {
                    removeLen += 1
                }
                edits.append((NSRange(location: entry.contentStart, length: removeLen), ""))
            }
        } else {
            for entry in nonBlank {
                edits.append((NSRange(location: entry.contentStart, length: 0), prefix))
            }
        }

        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        for edit in edits.reversed() {
            replaceCharacters(in: edit.range, with: edit.replacement)
        }
        undoManager?.endUndoGrouping()
        breakUndoCoalescing()

        let totalDelta = edits.reduce(0) { acc, edit in
            acc + (edit.replacement as NSString).length - edit.range.length
        }

        if selection.length == 0 {
            // Empty selection: only the caret's line was edited (at most). Adjust
            // caret by the delta of the edit on that line, snapping into the
            // edit's start if the caret was inside a removed marker.
            var caret = selection.location
            for edit in edits {
                let editEnd = edit.range.location + edit.range.length
                let delta = (edit.replacement as NSString).length - edit.range.length
                if edit.range.location >= caret {
                    // Insertion at or after caret leaves caret put (Xcode behavior
                    // for prefix-at-caret). Removal entirely after caret also
                    // leaves caret put.
                    continue
                }
                if editEnd > caret {
                    // Caret was inside the removed range — snap to its start.
                    caret = edit.range.location
                } else {
                    caret += delta
                }
            }
            textSelection = NSRange(location: caret, length: 0)
        } else {
            let firstStart = lineRanges.first!.location
            let originalLastEnd = lineRanges.last!.location + lineRanges.last!.length
            let newLength = max(0, (originalLastEnd - firstStart) + totalDelta)
            textSelection = NSRange(location: firstStart, length: newLength)
        }
    }

    private func indentLines(touching selection: NSRange) {
        let lineRanges = affectedLineRanges(for: selection)
        guard !lineRanges.isEmpty else { return }

        let indent = "\t"
        let indentLength = (indent as NSString).length

        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        for line in lineRanges.reversed() {
            replaceCharacters(in: NSRange(location: line.location, length: 0), with: indent)
        }
        undoManager?.endUndoGrouping()
        breakUndoCoalescing()

        let firstStart = lineRanges.first!.location
        let originalLastEnd = lineRanges.last!.location + lineRanges.last!.length
        let totalAdded = lineRanges.count * indentLength
        textSelection = NSRange(location: firstStart,
                                length: (originalLastEnd - firstStart) + totalAdded)
    }

    private func outdentLines(touching selection: NSRange) {
        let lineRanges = affectedLineRanges(for: selection)
        guard !lineRanges.isEmpty else { return }

        let fullText = (text ?? "") as NSString
        var removals: [(line: NSRange, removed: Int)] = []
        var totalRemoved = 0
        for line in lineRanges {
            guard line.length > 0 else {
                removals.append((line, 0))
                continue
            }
            let firstChar = fullText.substring(with: NSRange(location: line.location, length: 1))
            let removeLen = (firstChar == "\t" || firstChar == " ") ? 1 : 0
            removals.append((line, removeLen))
            totalRemoved += removeLen
        }

        guard totalRemoved > 0 else { return }

        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        for entry in removals.reversed() where entry.removed > 0 {
            replaceCharacters(in: NSRange(location: entry.line.location, length: entry.removed),
                              with: "")
        }
        undoManager?.endUndoGrouping()
        breakUndoCoalescing()

        if selection.length == 0 {
            // Empty selection: keep the caret on the same line, shifted left
            // by however many characters were stripped from before the caret.
            let lineStart = lineRanges[0].location
            let removed = removals[0].removed
            let originalLoc = selection.location
            let newLoc: Int
            if originalLoc < lineStart + removed {
                newLoc = lineStart
            } else {
                newLoc = originalLoc - removed
            }
            textSelection = NSRange(location: newLoc, length: 0)
        } else {
            let firstStart = lineRanges.first!.location
            let originalLastEnd = lineRanges.last!.location + lineRanges.last!.length
            let newLength = max(0, (originalLastEnd - firstStart) - totalRemoved)
            textSelection = NSRange(location: firstStart, length: newLength)
        }
    }

    /// Returns the per-line `NSRange`s touched by `selection`, walking the
    /// backing string a line at a time. If the selection ends right at a
    /// line start (length > 0), that trailing empty line is excluded so a
    /// sweep that just barely crosses into the next line doesn't indent it.
    private func affectedLineRanges(for selection: NSRange) -> [NSRange] {
        let fullText = (text ?? "") as NSString
        guard fullText.length > 0 || selection.location == 0 else { return [] }

        var working = selection
        if working.length > 0,
           working.location + working.length <= fullText.length,
           working.location + working.length > 0 {
            let prevIndex = working.location + working.length - 1
            let prevChar = fullText.substring(with: NSRange(location: prevIndex, length: 1))
            if prevChar == "\n" || prevChar == "\r" {
                working = NSRange(location: working.location, length: working.length - 1)
            }
        }

        // Anchor at a 0-length range so lineRange(for:) works at end-of-document.
        let anchor: NSRange
        if working.location > fullText.length {
            anchor = NSRange(location: fullText.length, length: 0)
        } else {
            anchor = working
        }
        let block = fullText.lineRange(for: anchor)

        var result: [NSRange] = []
        var loc = block.location
        let endLoc = max(block.location + block.length,
                         working.location + working.length)
        while loc < endLoc {
            let line = fullText.lineRange(for: NSRange(location: loc, length: 0))
            result.append(line)
            if line.length == 0 { break }
            loc = line.location + line.length
        }
        if result.isEmpty {
            result.append(NSRange(location: anchor.location, length: 0))
        }
        return result
    }
}
