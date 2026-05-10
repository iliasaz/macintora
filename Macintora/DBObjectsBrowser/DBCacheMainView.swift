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
    @State private var reportDisplayed = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var filterInspectorPresented = false
    @SectionedFetchRequest var items: SectionedFetchResults<String?, DBCacheObject>
    @State private var listSelection: SectionedFetchResults<String?, DBCacheObject>.Section.Element?
    @State private var commandsBox = DBBrowserCommandsBox()
    @FocusState private var focus: DBBrowserFocus?

    init(cache: DBCacheVM) {
        self.cache = cache
        // No fetch cap: rely on Core Data faulting + List's lazy row
        // materialisation. Effective infinite scroll for free.
        _items = SectionedFetchRequest(
            fetchRequest: DBCacheObject.fetchRequest(predicate: cache.searchCriteria.predicate),
            sectionIdentifier: \DBCacheObject.owner_,
            animation: .default)
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
            DBCacheSidebarList(items: items, listSelection: $listSelection)
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
        .searchable(text: query, placement: .sidebar, prompt: "Filter objects")
        .searchFocused($focus, equals: .search)
        .inspector(isPresented: $filterInspectorPresented) {
            QuickFilterView(quickFilters: $cache.searchCriteria)
                .inspectorColumnWidth(min: 220, ideal: 260, max: 360)
        }
        .background(WindowObserver { window in
            DBBrowserWindowRegistry.shared.register(vm: cache, window: window)
        })
        .onAppear {
            cache.store = injectedStore
            cache.keychain = keychain
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
        .focusedSceneValue(\.dbBrowserCommandsBox, commandsBox)
        .focusedSceneValue(\.dbBrowserIsReloading, cache.isReloading)
        .toolbar { toolbarContent }
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
            cache?.searchCriteria.searchText = ""
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
            Button { reportDisplayed.toggle() } label: {
                Label("Counts", systemImage: "sum")
            }
            .sheet(isPresented: $reportDisplayed) {
                cacheCountsSheet
            }
            .help("Show Cache counts")

            Button {
                filterInspectorPresented.toggle()
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
            .help("Filter")

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

    var query: Binding<String> {
        Binding {
            cache.searchCriteria.searchText
        } set: { newValue in
            listSelection = nil
            cache.searchCriteria.searchText = newValue
            items.nsPredicate = cache.searchCriteria.predicate
        }
    }
}

private struct DBCacheSidebarList: View {
    let items: SectionedFetchResults<String?, DBCacheObject>
    @Binding var listSelection: SectionedFetchResults<String?, DBCacheObject>.Section.Element?

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView.search
            } else {
                List(selection: $listSelection) {
                    ForEach(items) { section in
                        Section {
                            ForEach(section) { item in
                                DBCacheListEntryView(dbObject: item)
                                    .tag(item)
                            }
                        } header: {
                            Text(section.id ?? "(unknown)")
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}

struct DBCacheMainView_Previews: PreviewProvider {
    static var previews: some View {
        DBCacheMainView(cache: .init(preview: true))
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
            .frame(width: 800, height: 800)
    }
}
