//
//  EditorSelectionBridge.swift
//  Macintora
//
//  Pure, UI-free helpers for converting between the editor's `NSRange` selection
//  (what STTextView exposes) and the app's `Range<String.Index>` selection (what
//  `MainDocumentVM.getCurrentSql`, `format(of:)`, etc. accept). Kept standalone so
//  the round-trip behaviour can be unit-tested without spinning up an AppKit view.
//

import Foundation

enum EditorSelectionBridge {
    /// Convert an `NSRange` (UTF-16 code units) to a `Range<String.Index>` over
    /// `string`. Returns `nil` for `NSNotFound`, ranges past the end, or ranges
    /// that fall between code units.
    static func range(for nsRange: NSRange, in string: String) -> Range<String.Index>? {
        guard nsRange.location != NSNotFound else { return nil }
        return Range(nsRange, in: string)
    }

    /// Convert a `Range<String.Index>` to an `NSRange` (UTF-16 code units).
    /// Returns `nil` if the range lies outside `string`'s bounds.
    static func nsRange(for range: Range<String.Index>, in string: String) -> NSRange? {
        guard range.lowerBound >= string.startIndex,
              range.upperBound <= string.endIndex
        else { return nil }
        return NSRange(range, in: string)
    }

    /// Zero-length "no selection" range anchored at the start of `string`.
    static func emptyRange(in string: String) -> Range<String.Index> {
        string.startIndex ..< string.startIndex
    }

    /// Zero-length range at the end of `string`. Used after programmatic text
    /// replacements (e.g. format-in-place) to keep the caret in-bounds.
    static func endRange(in string: String) -> Range<String.Index> {
        string.endIndex ..< string.endIndex
    }
}
