//
//  KeyboardShortcuts.swift
//  Macintora
//
//  Source-of-truth list for the Macintora-specific keyboard shortcuts and
//  the read-only cheatsheet window that surfaces them. Adding a new
//  shortcut means updating `KeyboardShortcuts.groups` in one place — the
//  cheatsheet view renders straight from the same data the menu items use.
//
//  Shortcut glyphs are rendered via `Text("⇧⌘R").monospaced()` rather than
//  reconstructed from `EventModifiers`, matching the convention used by
//  most macOS cheatsheet panels.
//

import SwiftUI

struct KeyboardShortcutEntry: Identifiable, Hashable {
    let label: String
    let shortcut: String
    var id: String { label }
}

struct KeyboardShortcutGroup: Identifiable, Hashable {
    let title: String
    let entries: [KeyboardShortcutEntry]
    var id: String { title }
}

enum KeyboardShortcuts {
    static let groups: [KeyboardShortcutGroup] = [
        KeyboardShortcutGroup(title: "Database", entries: [
            KeyboardShortcutEntry(label: "Manage Connections…", shortcut: "⇧⌘K"),
            KeyboardShortcutEntry(label: "Database Browser", shortcut: "⇧⌘I"),
            KeyboardShortcutEntry(label: "Session Browser", shortcut: "⌃⇧⌘S"),
            KeyboardShortcutEntry(label: "Quick View", shortcut: "⌘I"),
        ]),
        KeyboardShortcutGroup(title: "Run", entries: [
            KeyboardShortcutEntry(label: "Run", shortcut: "⌘R"),
            KeyboardShortcutEntry(label: "Stop", shortcut: "⌘B"),
            KeyboardShortcutEntry(label: "Run Script", shortcut: "⇧⌘R"),
            KeyboardShortcutEntry(label: "Run From Cursor / Selection", shortcut: "⌥⌘R"),
            KeyboardShortcutEntry(label: "Explain Plan", shortcut: "⌘E"),
            KeyboardShortcutEntry(label: "Compile", shortcut: "⌥⌘C"),
            KeyboardShortcutEntry(label: "Format", shortcut: "⌃⌘F"),
        ]),
        KeyboardShortcutGroup(title: "Editor", entries: [
            KeyboardShortcutEntry(label: "Toggle Line Comment", shortcut: "⌘/"),
            KeyboardShortcutEntry(label: "Make Upper Case", shortcut: "⌘U"),
            KeyboardShortcutEntry(label: "Make Lower Case", shortcut: "⌘L"),
        ]),
        KeyboardShortcutGroup(title: "File", entries: [
            KeyboardShortcutEntry(label: "New Tab", shortcut: "⇧⌘T"),
        ]),
    ]

    /// Stable scene identifier used by `openWindow(id:)` and the matching
    /// `Window` declaration in `MacintoraApp`.
    static let windowID = "shortcuts"
}

struct KeyboardShortcutsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(KeyboardShortcuts.groups) { group in
                    KeyboardShortcutGroupView(group: group)
                }
            }
            .padding()
            .frame(minWidth: 360, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("keyboard.shortcuts.window")
    }
}

private struct KeyboardShortcutGroupView: View {
    let group: KeyboardShortcutGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.title)
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                ForEach(group.entries) { entry in
                    GridRow {
                        Text(entry.label)
                        Text(entry.shortcut)
                            .monospaced()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

#Preview {
    KeyboardShortcutsView()
}
