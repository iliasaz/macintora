//
//  DBCacheBrowserMainView.swift
//
//  Created by Ilia on 1/1/22.
//

import SwiftUI
import CoreData

struct DBCacheBrowserMainView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var searchCriteria: DBCacheSearchCriteria = DBCacheSearchCriteria()
    @SectionedFetchRequest(fetchRequest: DBCacheObject.fetchRequest(limit: 100), sectionIdentifier: \DBCacheObject.owner_, animation: .default) private var items
//    @State private var searchText = ""
//    var query: Binding<String> {
//        Binding {
//            searchText
//        } set: { newValue in
//            items.nsPredicate = newValue.isEmpty ? nil : NSPredicate(format: "name_ CONTAINS[c] %@", newValue)
//        }
//    }
    
    var filters: Binding<DBCacheSearchCriteria> {
        Binding {
            searchCriteria
        } set: { newValue in
            items.nsPredicate = newValue.predicate
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                QuickFilterView(quickFilters: filters)
                List {
                    ForEach(items) { section in
                        Section(header: Text(section.id ?? "(unknown)")) {
                            ForEach(section) { item in
                                NavigationLink {
                                    DBObjectDetailView(owner: item.owner, name: item.name)
                                        .frame(minWidth: 400, idealWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
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
                .toolbar {
                    ToolbarItem {
                        Button {} label: {
                            Label("Add Item", systemImage: "plus")
                        }
                    }
                }
                Text("Select an item")
            }
        }
    }
}

//struct GridControlGroupStyle: ControlGroupStyle {
//    func makeBody(configuration: Configuration) -> some View {
//        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60, maximum: .infinity), spacing: 5, alignment: .leading)], alignment: .leading, spacing: 5) {
//            configuration.content
//                .toggleStyle(.button)
//                .padding(0)
//        }
//    }
//}

struct QuickFilterView: View {
    @Binding var quickFilters: DBCacheSearchCriteria
    var body: some View {
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
        .padding()
    }
}





struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        DBCacheBrowserMainView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
