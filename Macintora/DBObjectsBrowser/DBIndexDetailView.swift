//
//  DBIndexDetailView.swift
//  DBObjectsBrowser
//
//  Created by Ilia on 6/20/22.
//

import SwiftUI
import CoreData


struct DBIndexDetailView: View {
    @Environment(\.managedObjectContext) var context
    @State private var selectedTab: String = "columns"
    @FetchRequest private var indexes: FetchedResults<DBCacheIndex>
    @FetchRequest private var columns: FetchedResults<DBCacheIndexColumn>
    private var dbObject: DBCacheObject
    
    let columnLabels = ["position", "columnName", "isDescending", "length"]
    let booleanColumnLabels = ["isDescending"]
    var columnSortFn = { (lhs: NSManagedObject, rhs: NSManagedObject) in (lhs as! DBCacheIndexColumn).position < (rhs as! DBCacheIndexColumn).position }

    init(dbObject: DBCacheObject) {
        self.dbObject = dbObject
        _indexes = FetchRequest<DBCacheIndex>(sortDescriptors: [], predicate: NSPredicate.init(format: "name_ = %@ and owner_ = %@", dbObject.name, dbObject.owner))
        _columns = FetchRequest<DBCacheIndexColumn>(sortDescriptors: [], predicate: NSPredicate.init(format: "indexName_ = %@ and owner_ = %@", dbObject.name, dbObject.owner))
    }
    
    var tableHeader: some View {
        HStack {
            VStack(alignment: .centreLine, spacing: 3) {
                FormField(label: "Partitioned?") {
                    Toggle("", isOn: .constant(indexes.first?.isPartitioned ?? false))
                }
                FormField(label: "Row Count") {
                    Text(indexes.first?.numRows.formatted() ?? Constants.nullValue)
                }
                
            }
            Spacer()
            VStack(alignment: .centreLine, spacing: 3) {
                FormField(label: "Last Analyzed") {
                    Text(indexes.first?.lastAnalyzed?.ISO8601Format() ?? Constants.nullValue)
                }
            }
            Spacer()
        }
        .padding()
    }
    
    var body: some View {
        VStack {
            tableHeader
            
            TabView(selection: $selectedTab) {
                DetailGridView(columns: Array(columns), columnLabels: columnLabels, booleanColumnLabels: booleanColumnLabels, columnSortFn: columnSortFn)
                    .frame(maxWidth: .infinity, minHeight: 100, idealHeight: 300, maxHeight: .infinity, alignment: .topLeading)
                    .tabItem {
                        Text("Columns")
                    }.tag("columns")

                Text("Index DDL")
                    .tabItem {
                        Text("SQL")
                    }.tag("sql")


            }
            .font(.headline)
        }
        .frame(minWidth: 200, idealWidth: 400, maxWidth: .infinity)
        .padding()
    }
}

//struct DBTableDetailView_Previews: PreviewProvider {
//    static var previews: some View {
//        var cache = DBCacheVM.init(preview: true)
//        let objCache = DBCacheObject(context: cache.persistenceController.container.viewContext)
//        objCache.owner = "OWNER"
//        objCache.name = "NAME"
//        objCache.type = "TABLE"
//        objCache.lastDDLDate = .now
//        return DBTableDetailView(dbObject: objCache)
//            .environment(\.managedObjectContext, cache.persistenceController.container.viewContext)
//    }
//}

