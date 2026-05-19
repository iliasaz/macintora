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
    @Binding var dbObject: DBCacheObject

    init(dbObject: Binding<DBCacheObject>) {
        self._dbObject = dbObject
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Columns", systemImage: "rectangle.split.3x1", value: DBIndexTab.columns) {
                TableIndexColumnsView(dbObject: dbObject)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
