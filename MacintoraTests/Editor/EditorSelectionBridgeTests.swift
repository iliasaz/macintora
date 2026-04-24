import XCTest
@testable import Macintora

/// Round-trip tests for `EditorSelectionBridge`. Covers the safety net the
/// wrapper relies on: `NSRange` (UTF-16 code units) must translate losslessly
/// to and from `Range<String.Index>` across ASCII, multi-byte, combining, and
/// trailing-edge inputs; invalid ranges must return `nil` rather than trapping.
final class EditorSelectionBridgeTests: XCTestCase {

    // MARK: - NSRange → Range<String.Index>

    func test_nsRangeToRange_asciiSelection() {
        let text = "SELECT * FROM dual"
        let nsRange = NSRange(location: 7, length: 1) // "*"
        let range = try? XCTUnwrap(EditorSelectionBridge.range(for: nsRange, in: text))
        XCTAssertEqual(range.map { String(text[$0]) }, "*")
    }

    func test_nsRangeToRange_startOfString() {
        let text = "abc"
        let range = EditorSelectionBridge.range(for: NSRange(location: 0, length: 0), in: text)
        XCTAssertEqual(range, text.startIndex ..< text.startIndex)
    }

    func test_nsRangeToRange_endOfString() {
        let text = "abc"
        let range = EditorSelectionBridge.range(for: NSRange(location: 3, length: 0), in: text)
        XCTAssertEqual(range, text.endIndex ..< text.endIndex)
    }

    func test_nsRangeToRange_notFoundReturnsNil() {
        let text = "abc"
        XCTAssertNil(EditorSelectionBridge.range(for: NSRange(location: NSNotFound, length: 0), in: text))
    }

    func test_nsRangeToRange_outOfBoundsReturnsNil() {
        let text = "abc"
        XCTAssertNil(EditorSelectionBridge.range(for: NSRange(location: 10, length: 1), in: text))
    }

    func test_nsRangeToRange_emojiIsMultiByteSafe() {
        // "🦉" is 2 UTF-16 code units (surrogate pair).
        let text = "a🦉b"
        let nsRange = NSRange(location: 1, length: 2) // just the owl
        let range = try? XCTUnwrap(EditorSelectionBridge.range(for: nsRange, in: text))
        XCTAssertEqual(range.map { String(text[$0]) }, "🦉")
    }

    // MARK: - Range<String.Index> → NSRange

    func test_rangeToNsRange_asciiSelection() {
        let text = "select * from dual"
        let lo = text.index(text.startIndex, offsetBy: 7)
        let hi = text.index(after: lo)
        let ns = try? XCTUnwrap(EditorSelectionBridge.nsRange(for: lo..<hi, in: text))
        XCTAssertEqual(ns, NSRange(location: 7, length: 1))
    }

    func test_rangeToNsRange_emptyAtEnd() {
        let text = "abc"
        let ns = try? XCTUnwrap(EditorSelectionBridge.nsRange(for: text.endIndex..<text.endIndex, in: text))
        XCTAssertEqual(ns, NSRange(location: 3, length: 0))
    }

    func test_rangeToNsRange_emptyString() {
        let text = ""
        let ns = try? XCTUnwrap(EditorSelectionBridge.nsRange(for: EditorSelectionBridge.emptyRange(in: text), in: text))
        XCTAssertEqual(ns, NSRange(location: 0, length: 0))
    }

    // MARK: - Round-trips

    func test_roundTrip_asciiIsIdentity() {
        let text = "line one\nline two"
        let original = NSRange(location: 5, length: 3)
        let bridged = try? XCTUnwrap(EditorSelectionBridge.range(for: original, in: text))
        let back = bridged.flatMap { EditorSelectionBridge.nsRange(for: $0, in: text) }
        XCTAssertEqual(back, original)
    }

    func test_roundTrip_emojiIsIdentity() {
        let text = "a🦉b🐍c"
        let original = NSRange(location: 3, length: 3) // "b🐍" incl. surrogate pair prefix
        let bridged = try? XCTUnwrap(EditorSelectionBridge.range(for: original, in: text))
        let back = bridged.flatMap { EditorSelectionBridge.nsRange(for: $0, in: text) }
        XCTAssertEqual(back, original)
    }

    func test_roundTrip_combiningMarkIsIdentity() {
        // "é" as LATIN SMALL E + COMBINING ACUTE = 2 UTF-16 units.
        let text = "cafe\u{0301}" // "café" via combining mark
        XCTAssertEqual(text.utf16.count, 5)
        let original = NSRange(location: 0, length: 5)
        let bridged = try? XCTUnwrap(EditorSelectionBridge.range(for: original, in: text))
        let back = bridged.flatMap { EditorSelectionBridge.nsRange(for: $0, in: text) }
        XCTAssertEqual(back, original)
    }

    // MARK: - Sentinel helpers

    func test_emptyRange_isStartZero() {
        let text = "hello"
        let range = EditorSelectionBridge.emptyRange(in: text)
        XCTAssertEqual(range, text.startIndex ..< text.startIndex)
        XCTAssertTrue(range.isEmpty)
    }

    func test_endRange_isEndZero() {
        let text = "hello"
        let range = EditorSelectionBridge.endRange(in: text)
        XCTAssertEqual(range, text.endIndex ..< text.endIndex)
        XCTAssertTrue(range.isEmpty)
    }
}
