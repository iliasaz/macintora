//
//  SQLParserHelper.swift
//  Macintora
//
//  One-shot parsing helper used by tests (and any code that needs an ad-hoc
//  parse result without driving the editor). Production hot-paths get their
//  tree from the Neon plugin via `SQLTreeStore` — they should not call this.
//

import Foundation
import STPluginNeon  // re-exports SwiftTreeSitter
import TreeSitterResource

enum SQLParserHelper {
    /// Parses `source` with the bundled Oracle SQL grammar and returns the
    /// resulting tree. Crashes on parser-init or parse failure since both
    /// indicate a programming error (grammar misconfigured, etc.) rather
    /// than user input we can recover from.
    static func parse(_ source: String) -> SwiftTreeSitter.Tree {
        let parser = Parser()
        let language = SwiftTreeSitter.Language(language: TreeSitterLanguage.sqlOrcl.parser)
        try! parser.setLanguage(language)
        // `parse` returns the parser's internal `MutableTree`. The `Tree`
        // wrapper isn't directly accessible, but `copy()` produces one.
        return parser.parse(source)!.copy()!
    }

    /// Test/debug aid: returns the tree's S-expression for the given source.
    static func sExpression(_ source: String) -> String {
        parse(source).rootNode?.sExpressionString ?? "<no tree>"
    }
}
