//
//  DBCacheListView.swift
//  Macintora
//
//  Created by Ilia Sazonov on 8/31/22.
//

import SwiftUI

struct DBCacheListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject var searchCriteria: DBCacheSearchCriteria
    @SectionedFetchRequest var items: SectionedFetchResults<String?, DBCacheObject>
    @State private var isItemSeleceted: Bool = false
    @State private var listSelection: SectionedFetchResults<String?, DBCacheObject>.Section.Element?
    @State private var totalCountMatched: Int = 0

    init( searchCriteria: DBCacheSearchCriteria, request: SectionedFetchRequest<String?, DBCacheObject>) {
        _searchCriteria = StateObject(wrappedValue: searchCriteria)
        _items = request
    }
    
    var filters: Binding<DBCacheSearchCriteria> {
        Binding {
            searchCriteria
        } set: { newValue in
            items.nsPredicate = newValue.predicate
            totalCountMatched = 0
        }
    }

    var body: some View {
        VStack {
            QuickFilterView(quickFilters: filters)
            
            List(selection: $listSelection) {
                ForEach(items) { section in
                    Section(header: Text(section.id ?? "(unknown)")) {
                        ForEach(section) { item in
                            NavigationLink (tag: item, selection: $listSelection) {
                                DBDetailView(dbObject: item)
                                    .frame(minWidth: 400, idealWidth: 600, maxWidth: .infinity, idealHeight: 1000, maxHeight: .infinity)
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
        .onReceive(items.publisher ) { items in
            totalCountMatched += items.count
            if totalCountMatched == 1 {
                listSelection = items[0]
            }
        }
    }
}

//struct DBCacheListView_Previews: PreviewProvider {
//    static var previews: some View {
//        DBCacheListView(searchCriteria: DBCacheSearchCriteria(), request: <#SectionedFetchRequest<String?, DBCacheObject>#>)
//            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
//    }
//}
