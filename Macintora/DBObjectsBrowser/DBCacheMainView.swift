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

struct DBCacheMainView: View {
    @ObservedObject var cache: DBCacheVM
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.connectionStore) private var injectedStore
    @Environment(\.keychainService) private var keychain
    @State private var reportDisplayed = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @SectionedFetchRequest var items: SectionedFetchResults<String?, DBCacheObject>
    @State private var listSelection: SectionedFetchResults<String?, DBCacheObject>.Section.Element?

    init(cache: DBCacheVM) {
        self.cache = cache
        _items = SectionedFetchRequest(
            fetchRequest: DBCacheObject.fetchRequest(limit: cache.searchLimit, predicate: cache.searchCriteria.predicate),
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
            VStack(alignment: .leading, spacing: 0) {
                headerView
                    .frame(minWidth: 200)
                QuickFilterView(quickFilters: $cache.searchCriteria)
                Spacer()
            }
            .padding()
        } content: {
            List(selection: $listSelection) {
                ForEach(items) { section in
                    Section(header: Text(section.id ?? "(unknown)")) {
                        ForEach(section) { item in
                            NavigationLink(value: item) {
                                DBCacheListEntryView(dbObject: item)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                        }
                    }
                }
            }
            .listStyle(SidebarListStyle())
        } detail: {
            if let selectedItem = listSelection {
                DBDetailView(dbObject: Binding(get: { selectedItem }, set: {_ in }))
                    .environmentObject(cache)
                    .frame(minWidth: 400, idealWidth: 600, maxWidth: .infinity, idealHeight: 1000, maxHeight: .infinity)
            } else {
                Text("Nothing selected")
            }
        }
        .searchable(text: query, placement: .sidebar, prompt: "type something")
        .background(WindowObserver { window in
            DBBrowserWindowRegistry.shared.register(vm: cache, window: window)
        })
        .onAppear {
            cache.store = injectedStore
            cache.keychain = keychain
            performAutoSelect()
        }
        .onDisappear {
            DBBrowserWindowRegistry.shared.deregister(vm: cache)
        }
        .onChange(of: cache.searchCriteria.predicate) { _, value in
            listSelection = nil
            items.nsPredicate = value
        }
        .onChange(of: items) { _, _ in
            performAutoSelect()
        }
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                Menu {
                    Button(cache.isReloading ? "Working..." : "Incremental Refresh") {
                        guard !cache.isReloading else { return }
                        cache.updateCache()
                    }
                    
                    Button(cache.isReloading ? "Working..." : "Full Refresh (No Vacuum)") {
                        guard !cache.isReloading else { return }
                        cache.updateCache(ignoreLastUpdate: true)
                    }
                    
                    Button(cache.isReloading ? "Working..." : "Full Refresh + Vacuum") {
                        guard !cache.isReloading else { return }
                        cache.updateCache(ignoreLastUpdate: true, withCleanup: true)
                    }

                    Button(cache.isReloading ? "Working..." : "Vacuum Only") {
                        guard !cache.isReloading else { return }
                        cache.updateCache(cleanupOnly: true)
                    }

                } label: {
                    Label(cache.isReloading ? "Working..." : "Refresh", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Refresh Cache")
                
                Button { cache.clearCache() } label: {
                    Label("Clear", systemImage: "trash")
                }
                .help("Clear Cache")
            }
            
            ToolbarItemGroup(placement: .status) {
                Button { reportDisplayed.toggle() } label: {
                    Label("Counts", systemImage: "sum")
                }
                .sheet(isPresented: $reportDisplayed) {
                    VStack {
                        Text(cache.reportCacheCounts())
                            .textSelection(.enabled)
                            .lineLimit(20)
                            .frame(width: 300.0, height: 200.0, alignment: .topLeading)
                            .padding()
                        Button { reportDisplayed.toggle() } label: { Text("Dismiss") }
                        .padding()
                    }.padding()
                }
                .help("Show Cache counts")
                
                Image(systemName: "arrow.triangle.2.circlepath")
                    .rotationEffect(Angle.degrees(cache.isReloading ? 360 : 0))
                    .animation(.linear(duration: 2.0).repeat(while: cache.isReloading, autoreverses: false), value: cache.isReloading)
                    .foregroundColor(cache.isReloading ? .red : .green)
            }
        }
    }
    
    var headerView: some View {
        // db name and cache update timestamp
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(cache.connDetails.tns)").font(.headline)
                Text("- \(cache.dbVersionFull ?? "(unknown)")")
            }
                .padding(.vertical,3)
            Text("Cache updated: \(cache.lastUpdatedStr)")
                .font(.subheadline)
                .padding(.horizontal)
        }
    }
    
    var query: Binding<String> {
        Binding {
            cache.searchCriteria.searchText
        } set: { newValue in
            listSelection = nil
            cache.searchCriteria.searchText = newValue
            items.nsPredicate = cache.searchCriteria.predicate
//            totalCountMatched = 0
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
