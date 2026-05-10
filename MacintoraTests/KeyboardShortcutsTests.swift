//
//  KeyboardShortcutsTests.swift
//  MacintoraTests
//
//  Sanity checks for the cheatsheet's source-of-truth list. The list
//  drives both the Help-menu cheatsheet window and (by convention) what
//  the menu items in `MainDocumentMenuCommands` / `EditorMenuCommands`
//  bind. Tests here lock in the entries so a typo or accidental drop
//  fails CI rather than only showing up in QA.
//

import XCTest
@testable import Macintora

final class KeyboardShortcutsTests: XCTestCase {

    func test_groupsAreNonEmpty() {
        XCTAssertFalse(KeyboardShortcuts.groups.isEmpty)
        for group in KeyboardShortcuts.groups {
            XCTAssertFalse(group.entries.isEmpty,
                           "group \(group.title) must have at least one entry")
        }
    }

    func test_groupTitlesAreUnique() {
        let titles = KeyboardShortcuts.groups.map(\.title)
        XCTAssertEqual(titles.count, Set(titles).count,
                       "duplicate group title in cheatsheet")
    }

    func test_entryLabelsAreUniqueWithinGroup() {
        for group in KeyboardShortcuts.groups {
            let labels = group.entries.map(\.label)
            XCTAssertEqual(labels.count, Set(labels).count,
                           "duplicate label in group \(group.title)")
        }
    }

    func test_shortcutsAreNonEmpty() {
        for group in KeyboardShortcuts.groups {
            for entry in group.entries {
                XCTAssertFalse(entry.shortcut.isEmpty,
                               "entry \(entry.label) must have a shortcut glyph")
            }
        }
    }

    func test_runGroup_containsExpectedCommands() {
        let runGroup = KeyboardShortcuts.groups.first { $0.title == "Run" }
        XCTAssertNotNil(runGroup)
        let labels = runGroup?.entries.map(\.label) ?? []
        XCTAssertTrue(labels.contains("Run"))
        XCTAssertTrue(labels.contains("Stop"))
        XCTAssertTrue(labels.contains("Run Script"))
        XCTAssertTrue(labels.contains("Run From Cursor / Selection"))
        XCTAssertTrue(labels.contains("Explain Plan"))
        XCTAssertTrue(labels.contains("Compile"))
        XCTAssertTrue(labels.contains("Format"))
    }

    func test_editorGroup_containsToggleLineComment() {
        let editor = KeyboardShortcuts.groups.first { $0.title == "Editor" }
        XCTAssertNotNil(editor)
        let toggle = editor?.entries.first { $0.label == "Toggle Line Comment" }
        XCTAssertEqual(toggle?.shortcut, "⌘/")
    }

    func test_runShortcuts_matchExpectedGlyphs() {
        let expected: [String: String] = [
            "Run": "⌘R",
            "Stop": "⌘B",
            "Run Script": "⇧⌘R",
            "Run From Cursor / Selection": "⌥⌘R",
            "Explain Plan": "⌘E",
            "Compile": "⌥⌘C",
            "Format": "⌃⌘F",
        ]
        let runGroup = KeyboardShortcuts.groups.first { $0.title == "Run" }
        for entry in runGroup?.entries ?? [] {
            XCTAssertEqual(entry.shortcut, expected[entry.label],
                           "unexpected shortcut for \(entry.label)")
        }
    }

    func test_windowID_isStable() {
        // The Help menu uses `openWindow(id:)` with this constant; the
        // matching `Window` scene declares the same id. Asserting it here
        // stops a silent typo from breaking the cheatsheet.
        XCTAssertEqual(KeyboardShortcuts.windowID, "shortcuts")
    }
}
