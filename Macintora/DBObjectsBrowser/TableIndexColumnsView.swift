//
//  TableIndexColumnsView.swift
//  Macintora
//

import CoreData
import SwiftUI

struct TableIndexColumnsView: View {
    @Environment(\.managedObjectContext) var context
    @FetchRequest private var columns: FetchedResults<DBCacheIndexColumn>
    @State private var selectedRow: DBCacheIndexColumn.ID?

    init(dbObject: DBCacheObject) {
        _columns = FetchRequest<DBCacheIndexColumn>(
            sortDescriptors: [NSSortDescriptor(key: "position", ascending: true)],
            predicate: NSPredicate(format: "indexName_ = %@ and owner_ = %@", dbObject.name, dbObject.owner)
        )
    }

    var body: some View {
        Table(columns, selection: $selectedRow) {
            TableColumn("Position") { value in
                Text(value.position.formatted())
            }
            TableColumn("Column Name", value: \.columnName)
            TableColumn("Descending") { value in
                BoolIndicator(value: value.isDescending)
            }
            TableColumn("Length") { value in
                Text(value.length.formatted())
            }
        }
        .font(.system(.body, design: .monospaced))
    }
}
