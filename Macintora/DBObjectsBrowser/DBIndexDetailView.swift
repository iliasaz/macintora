//
//  DBIndexDetailView.swift
//  DBObjectsBrowser
//
//  Created by Ilia on 6/20/22.
//

import SwiftUI
import CoreData

private enum DBIndexTab: String, CaseIterable, Codable {
    case columns
    case sql
}

struct DBIndexDetailView: View {
    @Environment(\.managedObjectContext) var context
    @AppStorage("dbIndexDetailSelectedTab") private var selectedTab: DBIndexTab = .columns
    @FetchRequest private var indexes: FetchedResults<DBCacheIndex>
    @FetchRequest private var columns: FetchedResults<DBCacheIndexColumn>
    @Binding var dbObject: DBCacheObject

    let columnLabels = ["position", "columnName", "isDescending", "length"]
    let booleanColumnLabels = ["isDescending"]
    var columnSortFn = { (lhs: NSManagedObject, rhs: NSManagedObject) in (lhs as! DBCacheIndexColumn).position < (rhs as! DBCacheIndexColumn).position }

    init(dbObject: Binding<DBCacheObject>) {
        self._dbObject = dbObject
        _indexes = FetchRequest<DBCacheIndex>(sortDescriptors: [], predicate: NSPredicate.init(format: "name_ = %@ and owner_ = %@", dbObject.name.wrappedValue, dbObject.owner.wrappedValue))
        _columns = FetchRequest<DBCacheIndexColumn>(sortDescriptors: [], predicate: NSPredicate.init(format: "indexName_ = %@ and owner_ = %@", dbObject.name.wrappedValue, dbObject.owner.wrappedValue))
    }

    private var indexForm: some View {
        Form {
            LabeledContent("Partitioned") {
                BoolIndicator(value: indexes.first?.isPartitioned ?? false)
            }
            LabeledContent("Row Count", value: indexes.first?.numRows.formatted() ?? Constants.nullValue)
            LabeledContent("Last Analyzed", value: indexes.first?.lastAnalyzed?.formatted(date: .abbreviated, time: .shortened) ?? Constants.nullValue)
        }
        .formStyle(.grouped)
    }

    var body: some View {
        VStack {
            indexForm

            TabView(selection: $selectedTab) {
                Tab("Columns", systemImage: "rectangle.split.3x1", value: DBIndexTab.columns) {
                    DetailGridView(rows: Array(columns).sorted(by: columnSortFn), columnLabels: columnLabels, booleanColumnLabels: booleanColumnLabels, rowSortFn: columnSortFn)
                        .id(dbObject.id)
                        .frame(maxWidth: .infinity, minHeight: 100, idealHeight: 300, maxHeight: .infinity, alignment: .topLeading)
                }

                Tab("SQL", systemImage: "doc.text", value: DBIndexTab.sql) {
                    ContentUnavailableView(
                        "Index DDL Not Available",
                        systemImage: "doc.text",
                        description: Text("DDL preview for indexes is not yet implemented.")
                    )
                }
            }
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
