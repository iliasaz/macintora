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
    @State private var showInspector = false

    init(dbObject: DBCacheObject) {
        _columns = FetchRequest<DBCacheTableColumn>(
            sortDescriptors: [NSSortDescriptor(keyPath: \DBCacheTableColumn.internalColumnID, ascending: true)],
            predicate: NSPredicate(format: "tableName_ = %@ and owner_ = %@", dbObject.name, dbObject.owner)
        )
    }

    @ViewBuilder
    fileprivate var selectedColumn: DBCacheTableColumn? {
        guard let id = selectedRow else { return nil }
        return columns.first { $0.id == id }
    }

    var body: some View {
        Table(columns, selection: $selectedRow) {
            TableColumn("Internal ID") { value in
                Text(value.internalColumnID.formatted())
            }
            TableColumn("Column Name", value: \.columnName)
            TableColumn("Data Type", value: \.dataType)
            TableColumn("Data Type Mod", value: \.dataTypeMod)
            TableColumn("Length") { value in
                Text(value.length.formatted())
            }
            TableColumn("Nullable") { value in
                BoolIndicator(value: value.isNullable)
            }
            TableColumn("Identity") { value in
                BoolIndicator(value: value.isIdentity)
            }
            TableColumn("Hidden") { value in
                BoolIndicator(value: value.isHidden)
            }
            TableColumn("Default") { value in
                Text(value.defaultValue ?? "")
            }
        }
        .font(.system(.body, design: .monospaced))
        .onChange(of: selectedRow) { showInspector = $0 != nil }
        .inspector(isPresented: $showInspector) {
            if let col = selectedColumn {
                ColumnInspector(column: col)
            } else {
                ContentUnavailableView("No column selected", systemImage: "rectangle.split.3x1")
            }
        }
        .inspectorColumnWidth(ideal: 280)
    }

    private struct ColumnInspector: View {
        let column: DBCacheTableColumn

        var body: some View {
            Form {
                Section("Identification") {
                    LabeledContent("Column ID", value: (column.columnID as? Int)?.formatted() ?? "")
                    LabeledContent("Internal ID", value: column.internalColumnID.formatted())
                    LabeledContent("Column Name", value: column.columnName)
                }

                Section("Type") {
                    LabeledContent("Data Type", value: column.dataType)
                    LabeledContent("Data Type Mod", value: column.dataTypeMod)
                    LabeledContent("Data Type Owner", value: column.dataTypeOwner)
                    LabeledContent("Length", value: column.length.formatted())
                    LabeledContent("Precision", value: (column.precision as? Int)?.formatted() ?? "")
                    LabeledContent("Scale", value: (column.scale as? Int)?.formatted() ?? "")
                }

                Section("Nulls") {
                    LabeledContent("Nullable", value: column.isNullable ? "Yes" : "No")
                    LabeledContent("Nulls", value: column.numNulls.formatted())
                    LabeledContent("Distinct", value: column.numDistinct.formatted())
                }

                Section("Attributes") {
                    LabeledContent("Identity", value: column.isIdentity ? "Yes" : "No")
                    LabeledContent("Hidden", value: column.isHidden ? "Yes" : "No")
                    LabeledContent("Virtual", value: column.isVirtual ? "Yes" : "No")
                    LabeledContent("Sys Gen", value: column.isSysGen ? "Yes" : "No")
                }

                Section("Default") {
                    Text(column.defaultValue ?? "")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(nil)
                }
            }
            .formStyle(.grouped)
        }
    }
}
