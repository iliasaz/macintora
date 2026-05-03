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

    /// Set true while we're applying a chosen completion. STTextView fires
    /// `didChangeTextIn` synchronously inside `replaceCharacters`, which
    /// would otherwise be interpreted as the user typing the inserted text
    /// and immediately re-pop the completion menu. We swallow the next
    /// notification by checking this flag in `handleTextChange`.
    private var isInsertingCompletion = false

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
        editorCompletionLog.info("items(): context=\(String(describing: context), privacy: .public) preferredOwner=\(owner, privacy: .public) (sort hint, not a filter) treeAvailable=\(tree != nil)")

        switch context {
        case .none:
            return []

        case .afterFromKeyword(let prefix):
            let tables = await dataSource.tables(search: prefix,
                                                 preferredOwner: owner,
                                                 limit: fetchLimit)
            editorCompletionLog.info("afterFromKeyword: search=\(prefix, privacy: .public) preferredOwner=\(owner, privacy: .public) → \(tables.count) tables")
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

        case .procedureCall(let packageName, let procedureName, let argumentIndex):
            return await procedureCallSignatures(packageName: packageName,
                                                 procedureName: procedureName,
                                                 currentArgumentIndex: argumentIndex,
                                                 owner: owner)

        case .identifierPrefix(let prefix):
            // Soft fallback: if the prefix is non-trivial, surface objects
            // across all cached schemas; the user's connected schema is
            // sorted first as a relevance hint.
            guard prefix.count >= 2 else { return [] }
            let objects = await dataSource.objects(search: prefix,
                                                   owner: nil,
                                                   preferredOwner: owner,
                                                   types: ["TABLE", "VIEW", "PACKAGE"],
                                                   limit: fetchLimit)
            editorCompletionLog.info("identifierPrefix: prefix=\(prefix, privacy: .public) preferredOwner=\(owner, privacy: .public) → \(objects.count) objects")
            return objects.map { MacintoraCompletionItem.make(from: $0) }
        }
    }

    /// Replaces the partial identifier under the cursor with the picked item's
    /// `insertText`. Falls back to plain insertion if no partial range exists.
    /// Signature-row insertions take a separate path: the cursor sits right
    /// after `(`, so there's no partial identifier to strip — just insert the
    /// named-arg template and park the caret at the first value slot.
    func insert(_ item: any STCompletionItem, into textView: STTextView) {
        guard let item = item as? MacintoraCompletionItem else { return }
        let source = textView.text ?? ""
        let nsSource = source as NSString
        let cursor = textView.selectedRange().location

        if let signature = item.signatureInsertion {
            let insertLocation = max(0, min(cursor, nsSource.length))
            isInsertingCompletion = true
            textView.replaceCharacters(in: NSRange(location: insertLocation, length: 0),
                                       with: signature.text)
            textView.textSelection = NSRange(location: insertLocation + signature.caretUTF16Offset,
                                             length: 0)
            isInsertingCompletion = false
            return
        }

        // Compute the range of the in-progress identifier preceding the
        // cursor — same backward scan the analyzer uses.
        var start = max(0, min(cursor, nsSource.length))
        while start > 0 {
            let c = nsSource.character(at: start - 1)
            guard let scalar = Unicode.Scalar(c), SourceScanner.isIdentifierChar(scalar) else { break }
            start -= 1
        }
        let replaceRange = NSRange(location: start, length: cursor - start)
        isInsertingCompletion = true
        textView.replaceCharacters(in: replaceRange, with: item.insertText)
        isInsertingCompletion = false
    }

    // MARK: - Auto-trigger

    /// Called from the editor's text-change delegate. Decides whether the
    /// keystroke is one that should pop the completion menu, and if so
    /// schedules a debounced `complete(_:)` call.
    func handleTextChange(_ textView: STTextView, replacement: String) {
        debounceTask?.cancel()

        // The text change is the result of accepting a popup item — don't
        // treat the inserted text as a fresh user keystroke and re-pop the
        // menu. The flag is reset by `insert(_:into:)` after the call
        // returns; STTextView fires the change notification synchronously.
        if isInsertingCompletion {
            editorCompletionLog.debug("auto-trigger skipped: completion insertion in progress")
            return
        }

        // Suppress while marked text (IME composition) is active.
        if textView.hasMarkedText() {
            editorCompletionLog.debug("auto-trigger skipped: marked text active")
            return
        }

        // Decide whether the keystroke is a completion trigger:
        //   * `.` after an identifier → dotted member
        //   * an identifier character with prefix length ≥ 1 → prefix typing
        guard shouldAutoTrigger(textView: textView, replacement: replacement) else {
            editorCompletionLog.debug("auto-trigger skipped: shouldAutoTrigger=false replacement=\(replacement, privacy: .public)")
            return
        }

        editorCompletionLog.debug("auto-trigger scheduled (debounce \(self.debounceInterval)) replacement=\(replacement, privacy: .public)")
        debounceTask = Task { [weak self, weak textView] in
            guard let self else { return }
            try? await Task.sleep(for: debounceInterval)
            if Task.isCancelled {
                editorCompletionLog.debug("auto-trigger cancelled after sleep")
                return
            }
            guard let textView else {
                editorCompletionLog.debug("auto-trigger: textView gone after sleep")
                return
            }
            editorCompletionLog.debug("auto-trigger firing: textView.complete(_:)")
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
        // `.` triggers dotted-member completion; `(` and `,` trigger the
        // signature popup for the enclosing call. The analyzer is the
        // authority on whether the cursor is actually inside a call — this
        // gate just decides whether to fire `complete(_:)` at all.
        if last == "." || last == "(" || last == "," { return true }
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
                                                search: prefix,
                                                limit: fetchLimit)
            for c in cols where !seen.contains(c.columnName) {
                seen.insert(c.columnName)
                items.append(MacintoraCompletionItem.make(from: c))
            }
        }
        return items
    }

    func dottedMemberSuggestions(qualifier: String,
                                 prefix: String,
                                 owner: String,
                                 source: String,
                                 tree: SwiftTreeSitter.Tree?,
                                 offset: Int) async -> [MacintoraCompletionItem] {
        let aliases = currentAliases(source: source, tree: tree, offset: offset)
        let upper = qualifier.uppercased()

        // 1) Alias → table columns. Aliases resolve unambiguously, so this
        // short-circuits the rest.
        if let resolved = aliases[upper] ?? nil {
            return await fetchColumns(table: resolved, prefix: prefix)
        }

        // 2) `qualifier.` is ambiguous without semantic resolution: it could
        // be `schema.object` *or* `package.member`, and a cached
        // `qualifier`-named TABLE could coexist with a `qualifier`-named
        // PACKAGE in another schema. Probe both in parallel and merge —
        // showing both kinds in the popup is the pragmatic answer.
        async let schemaObjects = dataSource.objects(
            search: prefix,
            owner: upper,
            types: ["TABLE", "VIEW", "PACKAGE"],
            limit: fetchLimit)
        async let packageMembers = packageMemberSuggestions(qualifier: upper,
                                                            prefix: prefix,
                                                            owner: owner)

        let objs = await schemaObjects
        let procs = await packageMembers
        if !objs.isEmpty || !procs.isEmpty {
            return objs.map { MacintoraCompletionItem.make(from: $0) } + procs
        }

        // 3) Treat as table → columns of any cached table with this name,
        // regardless of schema. The user typed an unqualified table name
        // and may legitimately be reaching across grants.
        return await dataSource
            .columns(tableName: upper, owner: nil, search: prefix, limit: fetchLimit)
            .map { MacintoraCompletionItem.make(from: $0) }
    }

    /// Resolves `qualifier` to a cached PACKAGE and surfaces its procedures
    /// and functions. Empty result when the qualifier doesn't name a package
    /// in any cached schema. The package is selected by `resolvePackage`'s
    /// preferred-owner-first ranking; cross-schema name collisions
    /// (rare — same package name in two schemas the user has cached) pick
    /// the connected schema if it has one, otherwise the alphabetically
    /// first match.
    private func packageMemberSuggestions(qualifier: String,
                                          prefix: String,
                                          owner: String) async -> [MacintoraCompletionItem] {
        guard let pkg = await dataSource.resolvePackage(name: qualifier,
                                                        preferredOwner: owner)
        else { return [] }
        let procedures = await dataSource.procedures(packageName: pkg.name,
                                                     owner: pkg.owner,
                                                     search: prefix,
                                                     limit: fetchLimit)
        // Collapse overloads — the row only shows the procedure name at this
        // point, so duplicate "DEBIT" rows would just look like noise. The
        // user picks a specific overload after typing `(`, where the
        // signature popup surfaces every overload with its parameter list.
        var seen = Set<String>()
        let unique = procedures.filter { seen.insert($0.procedureName).inserted }
        return unique.map { MacintoraCompletionItem.make(from: $0) }
    }

    /// Builds one popup row per overload of the call target, with the
    /// formatted parameter list as the primary text. Phase 2 scope is
    /// package members only — standalone procedures (no qualifier) are
    /// deferred to phase 3 and skipped here. The matching-arity overload
    /// is sorted first as a hint for which signature applies; the user
    /// can still arrow through the rest.
    private func procedureCallSignatures(packageName: String?,
                                         procedureName: String,
                                         currentArgumentIndex: Int,
                                         owner: String) async -> [MacintoraCompletionItem] {
        guard let packageName else {
            // Phase 3 will resolve the standalone via DBCacheObject lookup.
            editorCompletionLog.info("procedureCall: standalone procs deferred to phase 3 — skipping")
            return []
        }
        guard let pkg = await dataSource.resolvePackage(name: packageName,
                                                        preferredOwner: owner) else {
            editorCompletionLog.info("procedureCall: no cached package for \(packageName, privacy: .public)")
            return []
        }
        // procedures(...) does substring matching; filter the result to
        // exact-name overloads. Overload count is small (typically 1-3),
        // so the per-overload argument fetch is cheap.
        let upperProc = procedureName.uppercased()
        let allMatches = await dataSource.procedures(packageName: pkg.name,
                                                     owner: pkg.owner,
                                                     search: procedureName,
                                                     limit: fetchLimit)
        let overloads = allMatches.filter { $0.procedureName == upperProc }
        guard !overloads.isEmpty else {
            editorCompletionLog.info("procedureCall: \(pkg.name, privacy: .public).\(upperProc, privacy: .public) not in cache")
            return []
        }

        var rendered: [(item: MacintoraCompletionItem, arity: Int)] = []
        for overload in overloads {
            let args = await dataSource.procedureArguments(owner: overload.owner,
                                                           packageName: overload.packageName,
                                                           procedureName: overload.procedureName,
                                                           overload: overload.overload)
            rendered.append((MacintoraCompletionItem.make(signatureFrom: overload, arguments: args),
                             args.count))
        }
        // Bubble matching-arity overloads first; ties retain fetch order.
        let needed = currentArgumentIndex + 1
        return rendered
            .enumerated()
            .sorted { lhs, rhs in
                let lhsMatch = lhs.element.arity >= needed
                let rhsMatch = rhs.element.arity >= needed
                if lhsMatch != rhsMatch { return lhsMatch && !rhsMatch }
                return lhs.offset < rhs.offset
            }
            .map { $0.element.item }
    }

    private func fetchColumns(table: ResolvedTable, prefix: String) async -> [MacintoraCompletionItem] {
        let cols = await dataSource.columns(tableName: table.name,
                                            owner: table.owner,
                                            search: prefix,
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
