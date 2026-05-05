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
