//
//  TableView.swift
//  DBObjectsBrowser
//
//  Created by Ilia on 1/4/22.
//

import SwiftUI
import CoreData

/// Sub-tabs inside the "Details" tab for tables/views. Codable so we can
/// persist the last user-picked tab across selections.
private enum DBTableDetailTab: String, CaseIterable, Codable {
    case columns
    case indexes
    case triggers
    case sql
}

struct DBTableDetailView: View {
    @Environment(\.managedObjectContext) var context
    @AppStorage("dbTableDetailSelectedTab") private var selectedTab: DBTableDetailTab = .columns
    @FetchRequest private var tables: FetchedResults<DBCacheTable>
    @FetchRequest private var columns: FetchedResults<DBCacheTableColumn>
    @Binding var dbObject: DBCacheObject
    @State var cursorPosition = (0,0)
    @State private var selection: NSRange?

    let columnLabels = ["columnID", "columnName", "dataType", "dataTypeMod", "dataTypeOwner", "length", "precision", "scale", "isNullable", "numNulls", "numDistinct", "isIdentity", "isHidden", "isVirtual", "isSysGen", "defaultValue","internalColumnID", ]
    let booleanColumnLabels = ["isNullable", "isHidden", "isIdentity", "isSysGen", "isVirtual"]
    var columnSortFn = { (lhs: NSManagedObject, rhs: NSManagedObject) in (lhs as! DBCacheTableColumn).internalColumnID < (rhs as! DBCacheTableColumn).internalColumnID }

    init(dbObject: Binding<DBCacheObject>) {
        self._dbObject = dbObject
        _tables = FetchRequest<DBCacheTable>(sortDescriptors: [], predicate: NSPredicate.init(format: "name_ = %@ and owner_ = %@", dbObject.name.wrappedValue, dbObject.owner.wrappedValue))
        _columns = FetchRequest<DBCacheTableColumn>(sortDescriptors: [], predicate: NSPredicate.init(format: "tableName_ = %@ and owner_ = %@", dbObject.name.wrappedValue, dbObject.owner.wrappedValue))
    }

    var sqlText: String { tables.first?.sqltext ?? "" }

    private var tableHeader: some View {
        Form {
            LabeledContent("Partitioned") {
                BoolIndicator(value: tables.first?.isPartitioned ?? false)
            }
            LabeledContent("Row Count", value: tables.first?.numRows.formatted() ?? Constants.nullValue)
            LabeledContent("Last Analyzed", value: tables.first?.lastAnalyzed?.formatted(date: .abbreviated, time: .shortened) ?? Constants.nullValue)
        }
        .formStyle(.grouped)
    }

    private var viewHeader: some View {
        Form {
            LabeledContent("Editioning") {
                BoolIndicator(value: tables.first?.isEditioning ?? false)
            }
            LabeledContent("Read Only") {
                BoolIndicator(value: tables.first?.isReadOnly ?? false)
            }
        }
        .formStyle(.grouped)
    }

    var body: some View {
        VStack {
            if tables.first?.isView ?? false { viewHeader } else { tableHeader }

            TabView(selection: $selectedTab) {
                Tab("Columns", systemImage: "rectangle.split.3x1", value: DBTableDetailTab.columns) {
                    DetailGridView(rows: Array(columns).sorted(by: columnSortFn), columnLabels: columnLabels, booleanColumnLabels: booleanColumnLabels, rowSortFn: columnSortFn)
                        .id(dbObject.id)
                        .frame(maxWidth: .infinity, minHeight: 100, idealHeight: 300, maxHeight: .infinity, alignment: .topLeading)
                }

                if !(tables.first?.isView ?? false) {
                    Tab("Indexes", systemImage: "list.bullet.indent", value: DBTableDetailTab.indexes) {
                        TableIndexListView(dbObject: dbObject)
                            .frame(maxWidth: .infinity, minHeight: 100, idealHeight: 300, maxHeight: .infinity, alignment: .topLeading)
                    }

                    Tab("Triggers", systemImage: "bolt", value: DBTableDetailTab.triggers) {
                        TableTriggerListView(dbObject: dbObject)
                            .frame(maxWidth: .infinity, minHeight: 100, idealHeight: 300, maxHeight: .infinity, alignment: .topLeading)
                    }
                }

                if tables.first?.isView ?? false {
                    Tab("SQL", systemImage: "doc.text", value: DBTableDetailTab.sql) {
                        viewSqlTab
                    }
                }
            }
        }
        .padding()
    }

    private var viewSqlTab: some View {
        VStack {
            HStack {
                Spacer()
                Button("Format Source") {
                    let formatter = Formatter()
                    formatter.formattedSource = "...formatting, please wait..."

                    SwiftUIWindow.open { window in
                        let _ = (window.title = dbObject.name)
                        FormattedView(formatter: formatter, onDone: { window.close() })
                    }
                    .closeOnEscape(true)

                    formatter.formatSource(name: dbObject.name, text: tables.first?.sqltext)
                }
            }

            ScrollView {
                Text(sqlText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
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
