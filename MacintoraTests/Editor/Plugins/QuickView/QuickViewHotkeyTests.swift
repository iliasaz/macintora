//
//  QuickViewHotkeyTests.swift
//  MacintoraTests
//
//  Verifies the AppStorage-backed `QuickViewHotkey` enum: each preset maps
//  to the right key/modifier combo, and the raw-value round-trip used by
//  `EditorSettings`/`MainDocumentMenuCommands` to read the user's choice
//  out of `UserDefaults` doesn't drift.
//

import XCTest
import SwiftUI
@testable import Macintora

@MainActor
final class QuickViewHotkeyTests: XCTestCase {

    func test_default_isCmdI() {
        XCTAssertEqual(QuickViewHotkey.default, .cmdI)
    }

    func test_storageKey_isStable() {
        // The Settings picker and the menu command both read this raw
        // string. Renaming it would silently reset every user's preference,
        // so flag any drift loudly.
        XCTAssertEqual(QuickViewHotkey.storageKey, "editor.quickViewHotkey")
    }

    func test_allCases_haveDistinctRawValues() {
        let raws = Set(QuickViewHotkey.allCases.map(\.rawValue))
        XCTAssertEqual(raws.count, QuickViewHotkey.allCases.count,
                       "Raw values must be unique — they're stored in UserDefaults")
    }

    func test_allCases_haveDistinctDisplayNames() {
        let names = Set(QuickViewHotkey.allCases.map(\.displayName))
        XCTAssertEqual(names.count, QuickViewHotkey.allCases.count)
    }

    func test_cmdI_modifiersAndKey() {
        XCTAssertEqual(QuickViewHotkey.cmdI.keyEquivalent, "i")
        XCTAssertEqual(QuickViewHotkey.cmdI.modifiers, [.command])
    }

    func test_cmdShiftI_modifiers() {
        XCTAssertEqual(QuickViewHotkey.cmdShiftI.keyEquivalent, "i")
        XCTAssertEqual(QuickViewHotkey.cmdShiftI.modifiers, [.command, .shift])
    }

    func test_cmdF4_carriesFunctionKey() {
        let key = QuickViewHotkey.cmdF4.keyEquivalent
        XCTAssertNotNil(key)
        XCTAssertEqual(QuickViewHotkey.cmdF4.modifiers, [.command])
    }

    func test_disabled_hasNoKeyEquivalent() {
        XCTAssertNil(QuickViewHotkey.disabled.keyEquivalent,
                     "Disabled state must opt out of `.keyboardShortcut(...)`")
        XCTAssertEqual(QuickViewHotkey.disabled.modifiers, [])
    }

    func test_rawValueRoundTrip() {
        for hotkey in QuickViewHotkey.allCases {
            let restored = QuickViewHotkey(rawValue: hotkey.rawValue)
            XCTAssertEqual(restored, hotkey,
                           "raw value \(hotkey.rawValue) must round-trip through init")
        }
    }

    func test_unknownRawValue_returnsNil() {
        XCTAssertNil(QuickViewHotkey(rawValue: "ctrlSpace"),
                     "Unknown stored value must return nil so callers fall back to .default")
    }
}
