//
//  QuickViewController.swift
//  Macintora
//
//  Orchestrates the resolve → fetch → present pipeline. Each trigger (right-
//  click menu item, hotkey, ⌘+click) calls into the same async entry point;
//  re-entrant calls cancel the in-flight fetch so a quick double-trigger
//  doesn't leave a stale popover in the queue.
//
//  Owned by `MacintoraEditorRepresentable.Coordinator` alongside the
//  `CompletionCoordinator`. Both share the same `SQLTreeStore` and
//  `CompletionDataSource` instances.
//

import AppKit
import STTextView
import STPluginNeon  // re-exports SwiftTreeSitter
import os

@MainActor
final class QuickViewController {

    private let logger = Logger(subsystem: "com.iliasazonov.macintora",
                                category: "editor.quickview")
    private let resolver = ObjectAtCursorResolver()
    private let treeStore: SQLTreeStore
    private let dataSource: CompletionDataSource
    private let presenter: QuickViewPresenter
    private let defaultOwnerProvider: @MainActor () -> String
    /// Closure that opens the DB Browser pre-fetched on the resolved object.
    /// Issue #13 will replace the simple name-only filter with full schema +
    /// type pre-filter; today this just routes through the existing
    /// `\.openWindow(value: DBCacheInputValue(...))` plumbing.
    var openInBrowserHandler: ((ResolvedDBReference) -> Void)?
    private var inflight: Task<Void, Never>?

    init(textView: STTextView,
         treeStore: SQLTreeStore,
         dataSource: CompletionDataSource,
         defaultOwnerProvider: @escaping @MainActor () -> String) {
        self.treeStore = treeStore
        self.dataSource = dataSource
        self.defaultOwnerProvider = defaultOwnerProvider
        self.presenter = QuickViewPresenter(textView: textView)
    }

    // MARK: - Public triggers

    /// Trigger Quick View at the editor's current keyboard cursor.
    /// `textView` and the selection are read on the main actor inside this
    /// method; callers don't need to bridge.
    func triggerAtCursor(textView: STTextView) {
        let nsRange = textView.selectedRange()
        // Use the cursor location regardless of selection length — the user's
        // intent is "at the cursor", not "across the selection".
        let offset = nsRange.location
        trigger(textView: textView,
                utf16Offset: offset,
                anchor: .range(NSRange(location: offset, length: 0)))
    }

    /// Trigger Quick View from a content-coordinates click point. Used by
    /// the ⌘+Click monitor. The presenter anchors the popover at `point`
    /// instead of the resolved token's bounding rect — clicks land on a
    /// known location, so re-deriving the range frame is wasted work.
    func triggerAtClick(textView: STTextView,
                        point: CGPoint,
                        utf16Offset: Int) {
        trigger(textView: textView,
                utf16Offset: utf16Offset,
                anchor: .point(point))
    }

    /// Trigger Quick View at an explicit text offset (right-click menu path —
    /// the location is provided by STTextView's plugin event).
    func triggerAtTextLocation(textView: STTextView, utf16Offset: Int) {
        trigger(textView: textView,
                utf16Offset: utf16Offset,
                anchor: .range(NSRange(location: utf16Offset, length: 0)))
    }

    func dismiss() {
        inflight?.cancel()
        inflight = nil
        presenter.close()
    }

    // MARK: - Pipeline

    private func trigger(textView: STTextView,
                         utf16Offset: Int,
                         anchor: QuickViewPresenter.Anchor) {
        let source = textView.text ?? ""
        let tree = treeStore.tree
        let reference = resolver.resolve(utf16Offset: utf16Offset,
                                         source: source,
                                         tree: tree)
        guard reference != .unresolved else {
            logger.debug("QuickView: cursor not on a resolvable token")
            return
        }
        logger.info("QuickView trigger: \(String(describing: reference), privacy: .public)")

        // Replace any in-flight fetch.
        inflight?.cancel()
        let owner = defaultOwnerProvider()
        let dataSource = self.dataSource
        let presenter = self.presenter
        let openInBrowserHandler = self.openInBrowserHandler

        inflight = Task { [weak self] in
            let payload = await Self.fetchPayload(for: reference,
                                                  preferredOwner: owner,
                                                  dataSource: dataSource)
            if Task.isCancelled { return }
            guard let self else { return }
            // Re-anchor the actual text range now that we know what was
            // resolved — for `.range(.zero)` cursor-position triggers this
            // upgrades the anchor to the token's bounding box.
            let upgraded = Self.upgradeAnchor(anchor,
                                              reference: reference,
                                              source: source,
                                              utf16Offset: utf16Offset)
            let action: (() -> Void)? = openInBrowserHandler.map { handler in
                { handler(reference) }
            }
            self.presenter.present(payload: payload,
                                   anchor: upgraded,
                                   openInBrowserAction: action)
            _ = presenter // keep ARC honest about capture
        }
    }

    /// Routes a `ResolvedDBReference` to the right `CompletionDataSource`
    /// fetcher and packages the result as a `QuickViewPayload`. Returns
    /// `.notCached(reference:)` when no cache row matches — the popover's
    /// "not cached" state is the source of user feedback.
    ///
    /// `internal` so the test target can exercise the orchestration logic
    /// directly without instantiating an STTextView; the production caller
    /// is `trigger(textView:utf16Offset:anchor:)` above.
    @concurrent
    nonisolated static func fetchPayload(
        for reference: ResolvedDBReference,
        preferredOwner: String,
        dataSource: CompletionDataSource
    ) async -> QuickViewPayload {
        switch reference {
        case .schemaObject(let owner, let name):
            return await fetchSchemaObject(owner: owner,
                                           name: name,
                                           preferredOwner: preferredOwner,
                                           reference: reference,
                                           dataSource: dataSource)
        case .packageMember(let pkgOwner, let pkgName, let memberName):
            return await fetchPackageMember(packageOwner: pkgOwner,
                                            packageName: pkgName,
                                            memberName: memberName,
                                            preferredOwner: preferredOwner,
                                            reference: reference,
                                            dataSource: dataSource)
        case .column(let tableOwner, let tableName, let columnName):
            // Try column popover first; fall back to the parent table when
            // no column row exists in the cache (e.g. the column reference
            // is to a synonym or expression).
            if let payload = await dataSource.columnDetail(tableOwner: tableOwner,
                                                           tableName: tableName,
                                                           columnName: columnName) {
                return .column(payload)
            }
            // For the parent-table fallback we require *some* concrete
            // evidence the table exists — at minimum one cached column.
            // Otherwise `tableDetail` returns an empty-containers payload
            // for a totally-uncached table and we'd render a misleading
            // "0 columns / 0 indexes" popover instead of the honest
            // "not cached" placeholder.
            if let table = await dataSource.tableDetail(owner: tableOwner ?? preferredOwner,
                                                        name: tableName,
                                                        highlightedColumn: columnName),
               !table.columns.isEmpty {
                return .table(table)
            }
            return .notCached(reference: reference)
        case .unresolved:
            return .notCached(reference: reference)
        }
    }

    @concurrent
    nonisolated private static func fetchSchemaObject(
        owner: String?,
        name: String,
        preferredOwner: String,
        reference: ResolvedDBReference,
        dataSource: CompletionDataSource
    ) async -> QuickViewPayload {
        guard let resolved = await dataSource.resolveSchemaObject(owner: owner,
                                                                  name: name,
                                                                  preferredOwner: preferredOwner) else {
            // 2-part schema-object that didn't match — try the package-member
            // interpretation before giving up. Common case: user clicks on
            // `pkg.proc` outside an invocation context.
            if let owner {
                if let proc = await dataSource.procedureDetail(owner: preferredOwner,
                                                               packageName: owner,
                                                               procedureName: name,
                                                               overload: nil) {
                    return .procedure(proc)
                }
            }
            return .notCached(reference: reference)
        }

        switch resolved.objectType {
        case "TABLE", "VIEW", "MATERIALIZED VIEW":
            if let table = await dataSource.tableDetail(owner: resolved.owner,
                                                        name: resolved.name,
                                                        highlightedColumn: nil) {
                return .table(table)
            }
            return .notCached(reference: reference)
        case "PACKAGE", "PACKAGE BODY", "TYPE", "TYPE BODY":
            if let pkg = await dataSource.packageDetail(owner: resolved.owner,
                                                        name: resolved.name) {
                return .packageOrType(pkg)
            }
            return .notCached(reference: reference)
        case "PROCEDURE", "FUNCTION":
            if let proc = await dataSource.procedureDetail(owner: resolved.owner,
                                                           packageName: nil,
                                                           procedureName: resolved.name,
                                                           overload: nil) {
                return .procedure(proc)
            }
            // Procedure metadata sometimes isn't refreshed; show object-only.
            if let unknown = await dataSource.unknownObjectDetail(owner: resolved.owner,
                                                                  name: resolved.name) {
                return .unknownObject(unknown)
            }
            return .notCached(reference: reference)
        case "SYNONYM":
            // v1: don't chase synonyms; show the synonym as an unknown object
            // so the user can see it exists.
            if let unknown = await dataSource.unknownObjectDetail(owner: resolved.owner,
                                                                  name: resolved.name) {
                return .unknownObject(unknown)
            }
            return .notCached(reference: reference)
        default:
            if let unknown = await dataSource.unknownObjectDetail(owner: resolved.owner,
                                                                  name: resolved.name) {
                return .unknownObject(unknown)
            }
            return .notCached(reference: reference)
        }
    }

    @concurrent
    nonisolated private static func fetchPackageMember(
        packageOwner: String?,
        packageName: String,
        memberName: String,
        preferredOwner: String,
        reference: ResolvedDBReference,
        dataSource: CompletionDataSource
    ) async -> QuickViewPayload {
        // 1) Try the package-member interpretation.
        if let proc = await dataSource.procedureDetail(owner: packageOwner ?? preferredOwner,
                                                      packageName: packageName,
                                                      procedureName: memberName,
                                                      overload: nil) {
            return .procedure(proc)
        }
        // 2) Fall back to schema-qualified standalone object: treat the
        // qualifier as a schema and the member as the standalone object.
        if let resolved = await dataSource.resolveSchemaObject(owner: packageOwner ?? packageName,
                                                               name: memberName,
                                                               preferredOwner: preferredOwner) {
            return await fetchSchemaObject(owner: resolved.owner,
                                           name: resolved.name,
                                           preferredOwner: preferredOwner,
                                           reference: reference,
                                           dataSource: dataSource)
        }
        return .notCached(reference: reference)
    }

    /// Recovers a meaningful anchor rect when the original anchor was a
    /// zero-length range (cursor-only trigger). Walks the source around the
    /// cursor to find the identifier's bounds and re-anchors there.
    private static func upgradeAnchor(_ anchor: QuickViewPresenter.Anchor,
                                      reference: ResolvedDBReference,
                                      source: String,
                                      utf16Offset: Int) -> QuickViewPresenter.Anchor {
        if case .range(let r) = anchor, r.length > 0 { return anchor }
        if case .point = anchor { return anchor }

        let nsSource = source as NSString
        let safe = max(0, min(utf16Offset, nsSource.length))
        var start = safe
        while start > 0 {
            let c = nsSource.character(at: start - 1)
            guard let scalar = Unicode.Scalar(c), SourceScanner.isIdentifierChar(scalar) else { break }
            start -= 1
        }
        var end = safe
        while end < nsSource.length {
            let c = nsSource.character(at: end)
            guard let scalar = Unicode.Scalar(c), SourceScanner.isIdentifierChar(scalar) else { break }
            end += 1
        }
        guard end > start else { return anchor }
        return .range(NSRange(location: start, length: end - start))
    }
}
