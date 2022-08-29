//
//  DBCacheBrowserMainView.swift
//
//  Created by Ilia on 1/1/22.
//

import SwiftUI
import CoreData

extension Animation {
    func `repeat`(while expression: Bool, autoreverses: Bool = true) -> Animation {
        if expression {
            return self.repeatForever(autoreverses: autoreverses)
        } else {
            return self
        }
    }
}


struct DBCacheBrowserMainView: View {
    @State var connDetails: ConnectionDetails
    @ObservedObject var cache: DBCacheVM
    @State private var reportDisplayed = false
    
    init(connDetails: ConnectionDetails) {
        self.connDetails = connDetails
        self.cache = DBCacheVM(connDetails: connDetails)
    }
    
    var animation: Animation {
        Animation.linear
            .repeatForever(autoreverses: false)
    }
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 0) {
                headerView
                
                CacheList(searchCriteria: cache.searchCriteria)
                    .environment(\.managedObjectContext, cache.persistenceController.container.viewContext)
                    .toolbar {
                        ToolbarItem {
                            Button { cache.clearCache() } label: {
                                Label("Clear", systemImage: "trash")
                            }
                        }
                        ToolbarItem {
                            Button {
                                cache.updateCache()
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .rotationEffect(Angle.degrees(cache.isReloading ? 359 : 0))
                                    .animation(.linear(duration: 1.0).repeat(while: cache.isReloading, autoreverses: false), value: cache.isReloading)
                            }
                            .disabled(cache.isReloading)
                        }
                        ToolbarItem {
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
                        }
                }
                Spacer()
            }
            .padding(.vertical)
            .frame(minWidth: 300, idealWidth: 800, maxWidth: .infinity, minHeight: 600, idealHeight: 1000, maxHeight: .infinity)
        }
    }
    
    var headerView: some View {
        // db name and buttons
        VStack(alignment: .leading, spacing: 0) {
            Text("\(cache.connDetails.tns)").font(.headline) //.frame(alignment: .center)
                .padding(.horizontal)
                .padding(.vertical,3)
            // db details
            DisclosureGroup("DB Info") {
                VStack(alignment: .leading, spacing: 0) {
                    Text("DB version: \(cache.dbVersionFull ?? "(unknown)")")
                    Text("Cache updated: \(cache.lastUpdatedStr)")
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal)
        }
    }
}

public enum CacheFocusedView: Hashable {
    case objectList, quickFilter
}

struct CacheList: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject var searchCriteria: DBCacheSearchCriteria
    @SectionedFetchRequest(fetchRequest: DBCacheObject.fetchRequest(limit: 100), sectionIdentifier: \DBCacheObject.owner_, animation: .default) private var items
    
    init( searchCriteria: DBCacheSearchCriteria) {
        _searchCriteria = StateObject(wrappedValue: searchCriteria)
    }
    
    var filters: Binding<DBCacheSearchCriteria> {
        Binding {
            searchCriteria
        } set: { newValue in
            items.nsPredicate = newValue.predicate
        }
    }

    var body: some View {
        VStack {
            QuickFilterView(quickFilters: filters)
            
            List {
                ForEach(items) { section in
                    Section(header: Text(section.id ?? "(unknown)")) {
                        ForEach(section) { item in
                            NavigationLink {
                                switch item.type {
                                    case OracleObjectType.table.rawValue, OracleObjectType.view.rawValue: DBTableDetailView(dbObject: item)
                                            .frame(minWidth: 400, idealWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
                                    case OracleObjectType.type.rawValue, OracleObjectType.package.rawValue: DBSourceDetailView(dbObject: item)
                                            .frame(minWidth: 400, idealWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
                                    case OracleObjectType.index.rawValue: DBIndexDetailView(dbObject: item)
                                            .frame(minWidth: 400, idealWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
                                    default: EmptyView()
                                }
                            } label: {
                                DBCacheListEntryView(dbObject: item)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                        }
                    }
                }
            }
            .searchable(text: filters.searchText, placement: .sidebar, prompt: "type something")
            .listStyle(SidebarListStyle())
        }
    }
}

struct GridControlGroupStyle: ControlGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80, maximum: .infinity), spacing: 5, alignment: .leading)], alignment: .leading, spacing: 5) {
            configuration.content
                .toggleStyle(.checkbox)
                .padding(0)
        }
    }
}

struct QuickFilterView: View {
    @Binding var quickFilters: DBCacheSearchCriteria
    @State private var isQuickFilterViewExpanded = true

    var body: some View {
        DisclosureGroup("Quick Filters", isExpanded: $isQuickFilterViewExpanded) {
            VStack {
                ControlGroup {
                    Toggle("Tables", isOn: $quickFilters.showTables)
                    Toggle("Views", isOn: $quickFilters.showViews)
                    Toggle("Indexes", isOn: $quickFilters.showIndexes)
                    Toggle("Packages", isOn: $quickFilters.showPackages)
                    Toggle("Types", isOn: $quickFilters.showTypes)
                    Toggle("Procedures", isOn: $quickFilters.showProcedures)
                        .disabled(true)
                    Toggle("Functions", isOn: $quickFilters.showFunctions)
                        .disabled(true)
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
        .padding(.horizontal)
    }
}



//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        DBCacheBrowserMainView(cache: DBCacheVM(connDetails: ConnectionDetails(username: "apps", password: "apps", tns: "dmwoac", connectionRole: .regular)))
//    }
//}
