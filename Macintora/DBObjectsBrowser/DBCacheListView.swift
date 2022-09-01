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
//    @SectionedFetchRequest(fetchRequest: DBCacheObject.fetchRequest(limit: 100), sectionIdentifier: \DBCacheObject.owner_, animation: .default) private var items
    @SectionedFetchRequest var items: SectionedFetchResults<String?, DBCacheObject>

    init( searchCriteria: DBCacheSearchCriteria, request: SectionedFetchRequest<String?, DBCacheObject>) {
        _searchCriteria = StateObject(wrappedValue: searchCriteria)
        _items = request
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
                                DBDetailView(dbObject: item)
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
        }
    }
}

//struct DBCacheListView_Previews: PreviewProvider {
//    static var previews: some View {
//        DBCacheListView()
//    }
//}
