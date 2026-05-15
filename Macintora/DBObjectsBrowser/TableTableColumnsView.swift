//
//  TableTableColumnsView.swift
//  Macintora
//

import CoreData
import SwiftUI

struct TableTableColumnsView: View {
    @Environment(\.managedObjectContext) var context
    @FetchRequest private var columns: FetchedResults<DBCacheTableColumn>
    @State private var selectedRow: DBCacheTableColumn.ID?

    init(dbObject: DBCacheObject) {
        _columns = FetchRequest<DBCacheTableColumn>(
            sortDescriptors: [NSSortDescriptor(keyPath: \DBCacheTableColumn.internalColumnID, ascending: true)],
            predicate: NSPredicate(format: "tableName_ = %@ and owner_ = %@", dbObject.name, dbObject.owner)
        )
    }

    var body: some View {
        Table(columns, selection: $selectedRow) {
            TableColumn("Column Name", value: \.columnName)
            TableColumn("Data Type", value: \.dataType)
            TableColumn("Data Type Mod") { value in
                Text(value.dataTypeMod)
            }
            TableColumn("Data Type Owner") { value in
                Text(value.dataTypeOwner)
            }
            TableColumn("Length") { value in
                Text(value.length.formatted())
            }
            TableColumn("Precision") { value in
                Text((value.precision as? Int)?.formatted() ?? "")
            }
            TableColumn("Scale") { value in
                Text((value.scale as? Int)?.formatted() ?? "")
            }
            TableColumn("Nullable") { value in
                BoolIndicator(value: value.isNullable)
            }
            TableColumn("Identity") { value in
                BoolIndicator(value: value.isIdentity)
            }
            TableColumn("Default") { value in
                Text(value.defaultValue ?? "")
            }
        }
        .font(.system(.body, design: .monospaced))
    }
}
