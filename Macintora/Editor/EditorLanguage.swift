//
//  EditorLanguage.swift
//  Macintora
//
//  App-facing language enum for the editor. Mapped to Neon's `TreeSitterLanguage`
//  inside the wrapper when syntax highlighting is installed. The `.plsql` case is
//  a placeholder: until a tree-sitter-plsql grammar is vendored it falls back to
//  the ANSI SQL grammar.
//

import Foundation
import STPluginNeon
import TreeSitterResource

enum EditorLanguage: Sendable, Hashable {
    case sql
    case plsql

    /// Build a Neon syntax-highlighting plugin configured for this language.
    /// PL/SQL currently reuses the ANSI SQL grammar until a tree-sitter-plsql
    /// target is added. Isolated on `@MainActor` because `NeonPlugin` is.
    ///
    /// Note: fully-qualifying `STPluginNeonAppKit.Theme` avoids the name clash
    /// with the app-level `Theme` enum in `MacintoraApp.swift` (a light/dark
    /// `AppStorage` preference).
    @MainActor
    func neonPlugin(theme: STPluginNeonAppKit.Theme = .default) -> NeonPlugin {
        switch self {
        case .sql, .plsql:
            return NeonPlugin(theme: theme, language: .sql)
        }
    }
}
