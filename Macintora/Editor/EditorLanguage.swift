//
//  EditorLanguage.swift
//  Macintora
//
//  App-facing language enum for the editor. Mapped to Neon's `TreeSitterLanguage`
//  inside the wrapper when syntax highlighting is installed.
//

import Foundation
import STPluginNeon
import TreeSitterResource

enum EditorLanguage: Sendable, Hashable {
    case sql
    case plsql

    /// Build a Neon syntax-highlighting plugin configured for this language.
    /// Both `.sql` and `.plsql` route to the Oracle SQL/PL-SQL grammar
    /// (`tree-sitter-sql-orcl`), which parses SQL statements and PL/SQL
    /// blocks in a single grammar. The app-level distinction stays in case
    /// future divergence (snippets, default templates, etc.) needs it.
    /// Isolated on `@MainActor` because `NeonPlugin` is.
    ///
    /// Note: fully-qualifying `STPluginNeonAppKit.Theme` avoids the name clash
    /// with the app-level `Theme` enum in `MacintoraApp.swift` (a light/dark
    /// `AppStorage` preference).
    @MainActor
    func neonPlugin(theme: STPluginNeonAppKit.Theme = .default) -> NeonPlugin {
        switch self {
        case .sql, .plsql:
            return NeonPlugin(theme: theme, language: .sqlOrcl)
        }
    }
}
