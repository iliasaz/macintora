//
//  DBObjectsListView.swift
//  MacOra
//
//  Created by Ilia on 11/28/21.
//

import SwiftUI
import CoreData

struct DBObjectBrowserSearchState: Equatable, Codable {
    var searchText = ""
    var prefixString = ""
    var ownerString = ""
    var showTables = true
    var showViews = false
    var showPackages = false
    var showProcedures = false
    var showFunctions = false
}

struct GridControlGroupStyle: ControlGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60, maximum: .infinity), spacing: 5, alignment: .leading)], alignment: .leading, spacing: 5) {
            configuration.content
                .toggleStyle(.button)
                .padding(0)
        }
    }
}

struct SearchContent: View {
    var queryString: String
    @Environment(\.isSearching) var isSearching // 2
    
    var body: some View {
        VStack {
            Text(queryString)
            Text(isSearching ? "Searching!": "Not searching.")
        }
    }
}

struct DBObjectsBrowser: View {
    @ObservedObject var cache: DBCache
    @State var isTableSelected = false
//    @State var selectedDBObjectName: String = ""
//    @State var selectedDBObjectOwner: String = ""
//    @State var selectedTableName: String = ""
//    @State var selectedTableOwner: String = ""
//    private var quickFilters: Binding<DBObjectBrowserSearchState>
    @State private var quickFilters = DBObjectBrowserSearchState()
    @State private var dbDetailsExpanded = false
//    @FetchRequest(fetchRequest: DBObject.fetchRequest(), animation: .default) private var items: FetchedResults<DBObject>
    @FetchRequest(fetchRequest: DBCacheObject.fetchRequest(limit: 100)) private var items
    @Environment(\.managedObjectContext) private var viewContext
    
    var query: Binding<String> {
        Binding {
            quickFilters.searchText
        } set: { newValue in
            quickFilters.searchText = newValue
            items.nsPredicate = newValue.isEmpty ? nil : NSPredicate(format: "name_ CONTAINS[c] %@", newValue)
        }
    }
    
//    init(cache : DatabaseCache, quickFilters: Binding<DBObjectBrowserSearchState>) {
    init(cache: DBCache?) {
//        log.debug("initiating DBObjectsBrowser View")
        let cache = cache ?? DBCache(connDetails: ConnectionDetails())
        self.cache = cache
//        self.quickFilters = quickFilters
    }
    
    var body: some View {
        NavigationView {
            VStack {
                headerView
                quickFiltersView
                
                // actual list
                List(items, id: \.self) { obj in
                    NavigationLink(
                        destination: TableView(owner: obj.owner, name: obj.name)
                                                .frame(minWidth: 400, idealWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
                    ) {
                        DBObjectsListEntry(dbObject: obj)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                }
                
                .searchable(text: query, placement: .sidebar, prompt: "type to filter")
                .listStyle(SidebarListStyle())
            }
            SearchContent(queryString: quickFilters.searchText)
        }
        
        .padding()
        .frame(minWidth: 200, idealWidth: 500, maxWidth: .infinity, idealHeight: 500, maxHeight: .infinity)
        .environment(\.managedObjectContext, cache.persistentController.container.viewContext)
    }
    
    var headerView: some View {
        // db name and buttons
        VStack {
            HStack {
                Text("Connection: \(cache.connDetails.tns ?? "")").font(.headline).frame(alignment: .leading)
                Spacer()
                Button {
                    cache.updateCache()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath").foregroundColor(Color.blue)
                }
                .help("Refresh")
                .disabled(true
                )
                Button {
                    cache.reloadCache()
                } label: {
                    Image(systemName: "exclamationmark.arrow.triangle.2.circlepath").foregroundColor(Color.blue)
                }
                .help("Reload")
            }
            // db details
            DisclosureGroup("DB Info") {
                VStack(alignment: .leading, spacing: 0) {
                    Text("DB version: \(cache.dbVersionFull ?? "(unknown)")")
                    Text("Cache updated: \(cache.lastUpdatedStr)")
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    var quickFiltersView: some View {
        DisclosureGroup("Quick Filters") {
            VStack {
                ControlGroup {
                    Toggle("Tables", isOn: $quickFilters.showTables)
                    Toggle("Views", isOn: $quickFilters.showViews)
                    Toggle("Packages", isOn: $quickFilters.showPackages)
                    Toggle("Procedures", isOn: $quickFilters.showProcedures)
                    Toggle("Functions", isOn: $quickFilters.showFunctions)
                }
                .controlGroupStyle(GridControlGroupStyle())
                .padding(.horizontal)
                
                TextField("Schemas, ex. SYSTEM,SYS", text: $quickFilters.ownerString)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    .padding(.horizontal)
                
                TextField("Object Prefix, ex. DBMS,DBA", text: $quickFilters.prefixString)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }
}


struct LazyView<Content: View>: View {
    let build: () -> Content
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }
    var body: Content {
        build()
    }
}

struct DBObjectsBrowserView_Previews: PreviewProvider {
    static var previews: some View {
        var cache = DBCache.preview
        let searchState = DBObjectBrowserSearchState()
        DBObjectsBrowser(cache: cache)
            .environment(\.managedObjectContext, cache.persistentController.container.viewContext)
    }
}
