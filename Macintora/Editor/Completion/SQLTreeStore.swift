//
//  SQLTreeStore.swift
//  Macintora
//
//  Holds the latest tree-sitter parse tree produced by the Neon highlighting
//  plugin so completion code can run structural queries without spinning up
//  a second `Parser`. Updated on the main actor from `NeonPlugin.onTreeUpdated`.
//

import Foundation
import STPluginNeon  // re-exports SwiftTreeSitter

@MainActor
@Observable
final class SQLTreeStore {
    private(set) var tree: SwiftTreeSitter.Tree?

    init() {}

    func update(_ tree: SwiftTreeSitter.Tree) {
        self.tree = tree
    }

    /// Smallest enclosing node for the given byte offset, walking down from
    /// the root. The parser is fed UTF-16 LE, so `offset` is the byte offset
    /// into that representation: `nsString_utf16_offset * 2`. Returns nil
    /// when no tree has been received yet.
    func node(atByteOffset offset: UInt32) -> SwiftTreeSitter.Node? {
        guard let root = tree?.rootNode else { return nil }
        return root.descendant(in: offset..<offset)
    }
}
