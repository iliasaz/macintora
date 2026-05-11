//
//  DBCacheMainView.swift
//  Macintora
//
//  Created by Ilia Sazonov on 12/20/22.
//

import SwiftUI

struct DBCacheInputValue: Hashable, Codable, Equatable {
    let mainConnection: MainConnection
    let selectedOwner: String?
    let selectedObjectName: String?
    let selectedObjectType: String?
    let initialDetailTab: DBDetailTab?

    init(
        mainConnection: MainConnection,
        selectedOwner: String? = nil,
        selectedObjectName: String? = nil,
        selectedObjectType: String? = nil,
        initialDetailTab: DBDetailTab? = nil
    ) {
        self.mainConnection = mainConnection
        self.selectedOwner = selectedOwner
        self.selectedObjectName = selectedObjectName
        self.selectedObjectType = selectedObjectType
        self.initialDetailTab = initialDetailTab
    }

    /// Backward-compatible decoding: scenes persisted before this version lack
    /// the new fields; treat absent keys as nil rather than throwing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mainConnection     = try  c.decode(MainConnection.self,   forKey: .mainConnection)
        selectedOwner      = try? c.decodeIfPresent(String.self,   forKey: .selectedOwner)      ?? nil
        selectedObjectName = try? c.decodeIfPresent(String.self,   forKey: .selectedObjectName) ?? nil
        selectedObjectType = try? c.decodeIfPresent(String.self,   forKey: .selectedObjectType) ?? nil
        initialDetailTab   = try? c.decodeIfPresent(DBDetailTab.self, forKey: .initialDetailTab) ?? nil
    }

    static func preview() -> DBCacheInputValue {
        DBCacheInputValue(mainConnection: .preview())
    }
}

/// Search-field focus identifier. `@FocusState` toggled by ⌘F via the
/// `DBBrowserCommandsBox.focusSearch` hook.
private enum DBBrowserFocus: Hashable {
    case search
}

struct DBCacheMainView: View {
    @ObservedObject var cache: DBCacheVM
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.connectionStore) private var injectedStore
    @Environment(\.keychainService) private var keychain
    @Environment(\.openWindow) private var openWindow
    @State private var reportDisplayed = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var filterPopoverPresented = false
    @State private var searchPalettePresented = false
    /// Local mirror of the search field. Debounced into
    /// `cache.searchCriteria.searchText` so the predicate doesn't recompute
    /// on every keystroke (HIG: Item 18).
    @State private var pendingSearchText: String = ""
    /// Per-connection persisted "last selected object" as
    /// `owner|name|type`. Backed by UserDefaults (`@AppStorage` doesn't
    /// support `[String: String]` directly). Restored on first appear when
    /// no other selection pending was set by `DBCacheInputValue`.
    @SectionedFetchRequest var items: SectionedFetchResults<String?, DBCacheObject>
    @State private var listSelection: SectionedFetchResults<String?, DBCacheObject>.Section.Element?
    @State private var commandsBox = DBBrowserCommandsBox()
    @StateObject private var pinned: DBBrowserPinnedStore
    @FocusState private var focus: DBBrowserFocus?

    init(cache: DBCacheVM) {
        self.cache = cache
        // No fetch cap: rely on Core Data faulting + List's lazy row
        // materialisation. Effective infinite scroll for free.
        _items = SectionedFetchRequest(
            fetchRequest: DBCacheObject.fetchRequest(predicate: cache.searchCriteria.predicate),
            sectionIdentifier: \DBCacheObject.owner_,
            animation: .default)
        _pinned = StateObject(wrappedValue: DBBrowserPinnedStore(tns: cache.connDetails.tns))
    }

    /// Selects the pending object once `items` has been populated.
    private func performAutoSelect() {
        guard let name = cache.pendingSelectionName else { return }
        let owner = cache.pendingSelectionOwner
        let type  = cache.pendingSelectionType
        for section in items {
            for item in section {
                guard item.name == name else { continue }
                guard owner == nil || item.owner == owner else { continue }
                guard type  == nil || item.type  == type  else { continue }
                listSelection = item
                cache.pendingSelectionName  = nil
                cache.pendingSelectionOwner = nil
                cache.pendingSelectionType  = nil
                return
            }
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            DBBrowserSidebar(
                items: items,
                cache: cache,
                pinned: pinned,
                listSelection: $listSelection,
                onContextAction: handleRowAction
            )
            .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 480)
        } detail: {
            if let selectedItem = listSelection {
                DBDetailView(dbObject: Binding(get: { selectedItem }, set: {_ in }))
                    .environmentObject(cache)
                    .frame(minWidth: 400, idealWidth: 600, maxWidth: .infinity, idealHeight: 1000, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView.search
            } else {
                ContentUnavailableView(
                    "No Object Selected",
                    systemImage: "tablecells",
                    description: Text("Pick an object from the list to view details.")
                )
            }
        }
        .navigationTitle(cache.connDetails.tns)
        .navigationSubtitle(navigationSubtitle)
        .searchable(text: $pendingSearchText, placement: .sidebar, prompt: "Filter objects")
        .searchFocused($focus, equals: .search)
        .sheet(isPresented: $searchPalettePresented) {
            DBSearchPalette(
                tns: cache.connDetails.tns,
                onReveal: { obj in revealObject(obj) },
                onOpenInNewWindow: { obj in handleRowAction(.openInNewWindow, obj) }
            )
            .environment(\.managedObjectContext, viewContext)
        }
        .background(WindowObserver { window in
            DBBrowserWindowRegistry.shared.register(vm: cache, window: window)
        })
        .onAppear {
            cache.store = injectedStore
            cache.keychain = keychain
            pendingSearchText = cache.searchCriteria.searchText
            restoreLastSelectionIfNeeded()
            performAutoSelect()
            wireCommandsBox()
        }
        .onDisappear {
            DBBrowserWindowRegistry.shared.deregister(vm: cache)
        }
        .onChange(of: cache.searchCriteria) { _, value in
            listSelection = nil
            items.nsPredicate = value.predicate
            value.persist()
        }
        .onChange(of: items.count) { _, _ in
            performAutoSelect()
        }
        .onChange(of: listSelection) { _, newValue in
            saveLastSelection(newValue)
        }
        // Debounce search input: each new pendingSearchText cancels the
        // previous task; only an uncancelled run after 200ms commits to
        // the criteria. The new value compares unequal so the criteria
        // `onChange` updates the predicate exactly once per pause.
        .task(id: pendingSearchText) {
            // Skip the initial-mount no-op (pendingSearchText already in
            // sync with criteria after onAppear).
            if pendingSearchText == cache.searchCriteria.searchText { return }
            do {
                try await Task.sleep(for: .milliseconds(200))
            } catch {
                return
            }
            cache.searchCriteria.searchText = pendingSearchText
        }
        .focusedSceneValue(\.dbBrowserCommandsBox, commandsBox)
        .focusedSceneValue(\.dbBrowserIsReloading, cache.isReloading)
        .toolbar { toolbarContent }
    }

    /// Saves the last selected object to UserDefaults keyed by TNS. Intentionally
    /// no-op when `selected` is nil so transient filter-driven clears (e.g.
    /// search criteria mutation) don't wipe the persisted last-selection.
    private func saveLastSelection(_ selected: DBCacheObject?) {
        guard let obj = selected else { return }
        let tns = cache.connDetails.tns
        var dict = UserDefaults.standard.dictionary(forKey: "dbBrowserLastSelection") as? [String: String] ?? [:]
        dict[tns] = "\(obj.owner)|\(obj.name)|\(obj.type)"
        UserDefaults.standard.set(dict, forKey: "dbBrowserLastSelection")
        DBBrowserRecents.record(tns: tns, DBPinnedKey(obj))
    }

    /// Brings a palette-picked object into view: scopes the list to its type
    /// (so it definitely passes the filter), then routes the selection through
    /// the `pendingSelection*` mechanism so it lands after the list refreshes.
    private func revealObject(_ obj: DBCacheObject) {
        cache.searchCriteria.selectedTypeFilter = obj.type
        cache.pendingSelectionOwner = obj.owner
        cache.pendingSelectionName  = obj.name
        cache.pendingSelectionType  = obj.type
    }

    private func restoreLastSelectionIfNeeded() {
        guard cache.pendingSelectionName == nil else { return }
        let tns = cache.connDetails.tns
        guard
            let dict = UserDefaults.standard.dictionary(forKey: "dbBrowserLastSelection") as? [String: String],
            let encoded = dict[tns]
        else { return }
        let parts = encoded.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return }
        cache.pendingSelectionOwner = parts[0]
        cache.pendingSelectionName  = parts[1]
        cache.pendingSelectionType  = parts[2]
    }

    private func handleRowAction(_ action: DBCacheRowAction, _ obj: DBCacheObject) {
        switch action {
        case .copyName:
            copyToPasteboard(obj.name)
        case .copyQualifiedName:
            copyToPasteboard("\(obj.owner).\(obj.name)")
        case .reveal:
            listSelection = obj
        case .openInNewWindow:
            let value = DBCacheInputValue(
                mainConnection: MainConnection(mainConnDetails: cache.connDetails),
                selectedOwner: obj.owner,
                selectedObjectName: obj.name,
                selectedObjectType: obj.type
            )
            openWindow(value: value)
        case .editSource:
            Task(priority: .background) {
                if let url = await cache.editSource(dbObject: obj) {
                    await MainActor.run { NSWorkspace.shared.open(url) }
                }
            }
        }
    }

    private func copyToPasteboard(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }

    private var navigationSubtitle: String {
        let version = cache.dbVersionFull ?? "—"
        return "\(version) · updated \(cache.lastUpdatedStr)"
    }

    private func wireCommandsBox() {
        let cache = self.cache
        commandsBox.incrementalRefresh = { [weak cache] in
            guard let cache, !cache.isReloading else { return }
            cache.updateCache()
        }
        commandsBox.fullRefresh = { [weak cache] in
            guard let cache, !cache.isReloading else { return }
            cache.updateCache(ignoreLastUpdate: true)
        }
        commandsBox.fullRefreshAndCompact = { [weak cache] in
            guard let cache, !cache.isReloading else { return }
            cache.updateCache(ignoreLastUpdate: true, withCleanup: true)
        }
        commandsBox.compactOnly = { [weak cache] in
            guard let cache, !cache.isReloading else { return }
            cache.updateCache(cleanupOnly: true)
        }
        commandsBox.clear = { [weak cache] in
            cache?.clearCache()
        }
        commandsBox.showCounts = {
            self.reportDisplayed = true
        }
        commandsBox.focusSearch = {
            self.focus = .search
        }
        commandsBox.clearSearch = { [weak cache] in
            self.pendingSearchText = ""
            cache?.searchCriteria.searchText = ""
        }
        commandsBox.openSearchPalette = {
            self.searchPalettePresented = true
        }
        commandsBox.openFilterPopover = {
            self.filterPopoverPresented = true
        }
        commandsBox.selectMainTab = {
            UserDefaults.standard.set(DBDetailTab.main.rawValue, forKey: "dbDetailSelectedTab")
        }
        commandsBox.selectDetailsTab = {
            UserDefaults.standard.set(DBDetailTab.details.rawValue, forKey: "dbDetailSelectedTab")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .principal) {
            Menu {
                Button("Incremental Refresh") { commandsBox.incrementalRefresh?() }
                Button("Full Refresh") { commandsBox.fullRefresh?() }
                Button("Full Refresh & Compact") { commandsBox.fullRefreshAndCompact?() }
                Button("Compact Cache") { commandsBox.compactOnly?() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(cache.isReloading)
            .help("Refresh Cache")

            Button { commandsBox.clear?() } label: {
                Label("Clear", systemImage: "trash")
            }
            .help("Clear Cache")
            .disabled(cache.isReloading)
        }

        ToolbarItemGroup(placement: .status) {
            Button { searchPalettePresented = true } label: {
                Label("Search", systemImage: "magnifyingglass")
            }
            .help("Search objects (⌘K)")

            Button { reportDisplayed.toggle() } label: {
                Label("Counts", systemImage: "sum")
            }
            .sheet(isPresented: $reportDisplayed) {
                cacheCountsSheet
            }
            .help("Show Cache counts")

            Button {
                filterPopoverPresented.toggle()
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
            .help("Filter & scope")
            .popover(isPresented: $filterPopoverPresented, arrowEdge: .bottom) {
                QuickFilterView(quickFilters: $cache.searchCriteria)
                    .environment(\.managedObjectContext, viewContext)
            }

            if cache.isReloading {
                ProgressView()
                    .controlSize(.small)
                    .help("Refreshing cache…")
            }
        }
    }

    private var cacheCountsSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cache Counts").font(.headline)
            Text(cache.reportCacheCounts())
                .textSelection(.enabled)
                .monospaced()
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Spacer()
                Button("Done") { reportDisplayed = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 320, idealWidth: 360, minHeight: 200)
    }

}

/// Actions exposed via the sidebar row context menu (HIG, Item 24).
enum DBCacheRowAction {
    case copyName
    case copyQualifiedName
    case reveal
    case openInNewWindow
    case editSource
}

struct DBCacheMainView_Previews: PreviewProvider {
    static var previews: some View {
        DBCacheMainView(cache: .init(preview: true))
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
            .frame(width: 800, height: 800)
    }
}
