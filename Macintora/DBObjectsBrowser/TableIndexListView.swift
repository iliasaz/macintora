//
//  TableIndexListView.swift
//  DBObjectsBrowser
//
//  Created by Ilia on 6/24/22.
//

import SwiftUI
import CoreData

struct TableIndexListView: View {
    @Environment(\.managedObjectContext) var context
    @FetchRequest private var indexes: FetchedResults<DBCacheIndex>
    private var dbObject: DBCacheObject
    @State private var selectedIndexRow: DBCacheIndex.ID?


    init(dbObject: DBCacheObject) {
        self.dbObject = dbObject
        _indexes = FetchRequest<DBCacheIndex>(sortDescriptors: [NSSortDescriptor(key: "name_", ascending: true)], predicate: NSPredicate.init(format: "tableName_ = %@ and tableOwner_ = %@", dbObject.name, dbObject.owner))
    }

    var body: some View {
        Table(indexes, selection: $selectedIndexRow) {
            TableColumn("Index Name", value: \.name )
            TableColumn("Type", value: \.type)
            TableColumn("Index Owner", value: \.owner )
            TableColumn("Valid?") { value in
                BoolIndicator(value: value.isValid, trueColor: .green, falseColor: .red)
            }
            TableColumn("Visible?") { value in
                BoolIndicator(value: value.isVisible)
            }
            TableColumn("Unique?") { value in
                BoolIndicator(value: value.isUnique)
            }
            TableColumn("Tablespace", value: \.tablespaceName )
            TableColumn("Last Analyzed") { value in
                Text(value.lastAnalyzed?.formatted(date: .abbreviated, time: .shortened) ?? "")
            }
            TableColumn("Degree", value: \.degree )
        }
        .font(.system(.body, design: .monospaced))
    }

}

//struct TableIndexListView_Previews: PreviewProvider {
//    static var previews: some View {
//        TableIndexListView()
//    }
//}
