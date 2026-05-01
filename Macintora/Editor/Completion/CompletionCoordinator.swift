//
//  CompletionCoordinator.swift
//  Macintora
//
//  Glue between the analyzer, the alias resolver, the cache data source, and
//  STTextView's completion delegate. Holds per-editor state (debounce task,
//  cached default owner). Created and owned by `MacintoraEditorRepresentable`.
//

import AppKit
import STTextView
import STPluginNeon  // re-exports SwiftTreeSitter
import os

/// `@unchecked Sendable` because all stored state is either main-actor-bound
/// (debounceTask is only mutated from MainActor.assumeIsolated paths) or
/// immutable (`treeStore`, `dataSource`, `defaultOwnerProvider`, value-type
/// helpers). Marking the class `@MainActor` was rejected by the Swift 6.2
/// strict-concurrency checker when the editor's nonisolated `STTextViewDelegate`
/// witness needed to capture it across a `MainActor.assumeIsolated` boundary.
@MainActor
final class CompletionCoordinator: @unchecked Sendable {

    let treeStore: SQLTreeStore
    let dataSource: CompletionDataSource
    let defaultOwnerProvider: @MainActor () -> String
    private let analyzer = SQLContextAnalyzer()
    private let aliasResolver = AliasResolver()
    private let logger = Logger(subsystem: "com.iliasazonov.macintora",
                                category: "completion.coordinator")

    /// In-flight auto-trigger task; cancelled on each keystroke so we only
    /// fire `complete(_:)` after the user pauses.
    private var debounceTask: Task<Void, Never>?

    /// Maximum suggestions per fetch; keeps the popup table snappy.
    private let fetchLimit = 50

    /// Debounce window for auto-trigger; tuned for sub-perceptible latency
    /// without hammering the cache for every keystroke.
    private let debounceInterval: Duration = .milliseconds(120)

    init(treeStore: SQLTreeStore,
         dataSource: CompletionDataSource,
         defaultOwnerProvider: @escaping @MainActor () -> String) {
        self.treeStore = treeStore
        self.dataSource = dataSource
        self.defaultOwnerProvider = defaultOwnerProvider
    }

    // MARK: - STTextView delegate entry points

    /// Returns suggestion items for the popup. Called from the textView's
    /// async completion delegate; safe to await here. Returns the concrete
    /// Sendable item type so the caller can cross actor boundaries safely.
    func items(for textView: STTextView, atUTF16Offset offset: Int) async -> [MacintoraCompletionItem] {
        let source = textView.text ?? ""
        let tree = treeStore.tree
        let context = analyzer.analyze(source: source, tree: tree, utf16Offset: offset)

        let owner = defaultOwnerProvider()

        switch context {
        case .none:
            return []

        case .afterFromKeyword(let prefix):
            let tables = await dataSource.tables(prefix: prefix,
                                                 defaultOwner: owner,
                                                 limit: fetchLimit)
            return tables.map { MacintoraCompletionItem.make(from: $0) }

        case .columnReference(let qualifier, let prefix):
            return await columnSuggestions(qualifier: qualifier,
                                           prefix: prefix,
                                           source: source,
                                           tree: tree,
                                           offset: offset)

        case .dottedMember(let qualifier, let prefix):
            return await dottedMemberSuggestions(qualifier: qualifier,
                                                 prefix: prefix,
                                                 owner: owner,
                                                 source: source,
                                                 tree: tree,
                                                 offset: offset)

        case .identifierPrefix(let prefix):
            // Soft fallback: if the prefix is non-trivial, surface objects
            // from the user's schema. Avoids spamming on a single keystroke.
            guard prefix.count >= 2 else { return [] }
            let objects = await dataSource.objects(prefix: prefix,
                                                   owner: owner,
                                                   types: ["TABLE", "VIEW", "PACKAGE"],
                                                   limit: fetchLimit)
            return objects.map { MacintoraCompletionItem.make(from: $0) }
        }
    }

    /// Replaces the partial identifier under the cursor with the picked item's
    /// `insertText`. Falls back to plain insertion if no partial range exists.
    func insert(_ item: any STCompletionItem, into textView: STTextView) {
        guard let item = item as? MacintoraCompletionItem else { return }
        let source = textView.text ?? ""
        let nsSource = source as NSString
        let cursor = textView.selectedRange().location

        // Compute the range of the in-progress identifier preceding the
        // cursor — same backward scan the analyzer uses.
        var start = max(0, min(cursor, nsSource.length))
        while start > 0 {
            let c = nsSource.character(at: start - 1)
            guard let scalar = Unicode.Scalar(c), SourceScanner.isIdentifierChar(scalar) else { break }
            start -= 1
        }
        let replaceRange = NSRange(location: start, length: cursor - start)
        textView.replaceCharacters(in: replaceRange, with: item.insertText)
    }

    // MARK: - Auto-trigger

    /// Called from the editor's text-change delegate. Decides whether the
    /// keystroke is one that should pop the completion menu, and if so
    /// schedules a debounced `complete(_:)` call.
    func handleTextChange(_ textView: STTextView, replacement: String) {
        debounceTask?.cancel()

        // Suppress while marked text (IME composition) is active.
        if textView.hasMarkedText() { return }

        // Decide whether the keystroke is a completion trigger:
        //   * `.` after an identifier → dotted member
        //   * an identifier character with prefix length ≥ 1 → prefix typing
        guard shouldAutoTrigger(textView: textView, replacement: replacement) else { return }

        debounceTask = Task { [weak self, weak textView] in
            guard let self else { return }
            try? await Task.sleep(for: debounceInterval)
            if Task.isCancelled { return }
            guard let textView else { return }
            textView.complete(self)
        }
    }

    /// Cancel any scheduled auto-trigger. Caller should invoke this when the
    /// cursor moves away from the identifier or the popup should dismiss.
    func cancelPending() {
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func shouldAutoTrigger(textView: STTextView, replacement: String) -> Bool {
        guard let last = replacement.unicodeScalars.last else { return false }
        if last == "." { return true }
        if SourceScanner.isIdentifierChar(last) {
            // Require at least one identifier character before the cursor to
            // avoid popping for a stray keystroke.
            let source = textView.text ?? ""
            let cursor = textView.selectedRange().location
            return SourceScanner.scan(source: source, utf16Offset: cursor).prefix.count >= 1
        }
        return false
    }

    // MARK: - Column / dotted-member resolution

    private func columnSuggestions(qualifier: String?,
                                   prefix: String,
                                   source: String,
                                   tree: SwiftTreeSitter.Tree?,
                                   offset: Int) async -> [MacintoraCompletionItem] {
        let aliases = currentAliases(source: source, tree: tree, offset: offset)

        // Resolve qualifier through alias map first; fall back to treating it
        // as a literal table name.
        if let qualifier {
            let upper = qualifier.uppercased()
            if let resolved = aliases[upper] ?? nil {
                return await fetchColumns(table: resolved, prefix: prefix)
            }
            // Unknown alias — try direct lookup against the user's schema.
            return await fetchColumns(table: ResolvedTable(owner: nil, name: upper),
                                      prefix: prefix)
        }

        // No qualifier: union columns of every aliased table in scope.
        var seen = Set<String>()
        var items: [MacintoraCompletionItem] = []
        for resolved in aliases.values.compactMap({ $0 }) {
            let cols = await dataSource.columns(tableName: resolved.name,
                                                owner: resolved.owner,
                                                prefix: prefix,
                                                limit: fetchLimit)
            for c in cols where !seen.contains(c.columnName) {
                seen.insert(c.columnName)
                items.append(MacintoraCompletionItem.make(from: c))
            }
        }
        return items
    }

    private func dottedMemberSuggestions(qualifier: String,
                                         prefix: String,
                                         owner: String,
                                         source: String,
                                         tree: SwiftTreeSitter.Tree?,
                                         offset: Int) async -> [MacintoraCompletionItem] {
        let aliases = currentAliases(source: source, tree: tree, offset: offset)
        let upper = qualifier.uppercased()

        // 1) Alias → table columns.
        if let resolved = aliases[upper] ?? nil {
            return await fetchColumns(table: resolved, prefix: prefix)
        }

        // 2) Treat as schema → list its objects (tables/views/packages).
        let objects = await dataSource.objects(
            prefix: prefix,
            owner: upper,
            types: ["TABLE", "VIEW", "PACKAGE"],
            limit: fetchLimit)
        if !objects.isEmpty {
            return objects.map { MacintoraCompletionItem.make(from: $0) }
        }

        // 3) Treat as table → its columns under the user's schema.
        return await dataSource
            .columns(tableName: upper, owner: owner, prefix: prefix, limit: fetchLimit)
            .map { MacintoraCompletionItem.make(from: $0) }
    }

    private func fetchColumns(table: ResolvedTable, prefix: String) async -> [MacintoraCompletionItem] {
        let cols = await dataSource.columns(tableName: table.name,
                                            owner: table.owner,
                                            prefix: prefix,
                                            limit: fetchLimit)
        return cols.map { MacintoraCompletionItem.make(from: $0) }
    }

    private func currentAliases(source: String,
                                tree: SwiftTreeSitter.Tree?,
                                offset: Int) -> [String: ResolvedTable?] {
        guard let tree else { return [:] }
        // Parser uses UTF-16 LE; byte offset is `utf16Offset * 2`.
        let cap = source.utf16.count
        let units = max(0, min(offset, cap))
        let byteOffset = UInt32(units * 2)
        guard let node = tree.rootNode?.descendant(in: byteOffset..<byteOffset)
        else { return [:] }
        return aliasResolver.aliases(near: node, source: source)
    }
}
