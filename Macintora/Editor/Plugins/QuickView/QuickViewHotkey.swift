//
//  QuickViewHotkey.swift
//  Macintora
//
//  AppStorage-backed enum of user-selectable hotkeys for the Quick View
//  feature. v1 ships a small preset list; a free-form key recorder is a
//  follow-up.
//

import SwiftUI

enum QuickViewHotkey: String, CaseIterable, Identifiable, Sendable {
    case cmdI = "cmdI"
    case cmdF4 = "cmdF4"
    case cmdShiftI = "cmdShiftI"
    case disabled = "disabled"

    static let storageKey = "editor.quickViewHotkey"
    static let `default`: QuickViewHotkey = .cmdI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cmdI:      return "⌘I"
        case .cmdF4:     return "⌘F4"
        case .cmdShiftI: return "⌘⇧I"
        case .disabled:  return "Disabled"
        }
    }

    /// `KeyEquivalent` for SwiftUI `.keyboardShortcut(...)`. Returns nil for
    /// the disabled state so the menu item can be omitted entirely.
    var keyEquivalent: KeyEquivalent? {
        switch self {
        case .cmdI, .cmdShiftI: return "i"
        case .cmdF4:            return KeyEquivalent(Character(UnicodeScalar(NSF4FunctionKey)!))
        case .disabled:         return nil
        }
    }

    var modifiers: EventModifiers {
        switch self {
        case .cmdI:      return [.command]
        case .cmdF4:     return [.command]
        case .cmdShiftI: return [.command, .shift]
        case .disabled:  return []
        }
    }
}
