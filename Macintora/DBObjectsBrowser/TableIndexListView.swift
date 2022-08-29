//
//  TableIndexListView.swift
//  DBObjectsBrowser
//
//  Created by Ilia on 6/24/22.
//

import SwiftUI
import CoreData
import SwiftOracle

struct TableIndexListView: View {
    @Environment(\.managedObjectContext) var context
    @FetchRequest private var indexes: FetchedResults<DBCacheIndex>
//    @FetchRequest private var indexColumns: FetchedResults<DBCacheIndexColumn>
//    @FetchRequest private var columns: FetchedResults<DBCacheIndexColumn>
    private var dbObject: DBCacheObject
    @State private var selectedIndexRow: DBCacheIndex.ID?
    
    
    init(dbObject: DBCacheObject) {
        self.dbObject = dbObject
        _indexes = FetchRequest<DBCacheIndex>(sortDescriptors: [], predicate: NSPredicate.init(format: "tableName_ = %@ and tableOwner_ = %@", dbObject.name, dbObject.owner))
//        _indexColumns = FetchRequest<DBCacheIndexColumn>(sortDescriptors: [], predicate: NSPredicate.init(format: "", selectedRow as! CVarArg))
    }
    
    var body: some View {
        Table(indexes, selection: $selectedIndexRow) {
            TableColumn("Index Name", value: \.name )
            TableColumn("Type", value: \.type)
            TableColumn("Index Owner", value: \.owner )
            TableColumn("Valid?") { value in
                Toggle("", isOn: Binding(get: {value.isValid}, set: {_ in }))
                    .toggleStyle(.checkbox)
            }
            TableColumn("Visible?") { value in
                Toggle("", isOn: Binding(get: {value.isVisible}, set: {_ in }))
                    .toggleStyle(.checkbox)
            }
            TableColumn("Unique?") { value in
                Toggle("", isOn: Binding(get: {value.isUnique}, set: {_ in }))
                    .toggleStyle(.checkbox)
            }
            TableColumn("Tablespace", value: \.tablespaceName )
            TableColumn("Last Analyzed") { value in
                Text(value.lastAnalyzed?.ISO8601Format() ?? "")
            }
            TableColumn("Degree", value: \.degree )
            TableColumn("Tablespace", value: \.tablespaceName )
            
        }
        .font(Font(NSFont(name: "Source Code Pro", size: NSFont.systemFontSize)!))
    }
}

//struct TableIndexListView_Previews: PreviewProvider {
//    static var previews: some View {
//        TableIndexListView()
//    }
//}
