//
//  TableView.swift
//  DBObjectsBrowser
//
//  Created by Ilia on 1/4/22.
//

import SwiftUI
import CoreData
import CodeEditor

struct DBTableDetailView: View {
    @Environment(\.managedObjectContext) var context
    @State private var selectedTab: String = "columns"
    @FetchRequest private var tables: FetchedResults<DBCacheTable>
    @FetchRequest private var columns: FetchedResults<DBCacheTableColumn>
    private var dbObject: DBCacheObject
    
    let columnLabels = ["columnID", "columnName", "dataType", "dataTypeMod", "dataTypeOwner", "length", "precision", "scale", "isNullable", "numNulls", "numDistinct", "isIdentity", "isHidden", "isVirtual", "isSysGen", "defaultValue","internalColumnID", ]
    let booleanColumnLabels = ["isNullable", "isHidden", "isIdentity", "isSysGen", "isVirtual"]
    var columnSortFn = { (lhs: NSManagedObject, rhs: NSManagedObject) in (lhs as! DBCacheTableColumn).internalColumnID < (rhs as! DBCacheTableColumn).internalColumnID }

    init(dbObject: DBCacheObject) {
        self.dbObject = dbObject
        _tables = FetchRequest<DBCacheTable>(sortDescriptors: [], predicate: NSPredicate.init(format: "name_ = %@ and owner_ = %@", dbObject.name, dbObject.owner))
        _columns = FetchRequest<DBCacheTableColumn>(sortDescriptors: [], predicate: NSPredicate.init(format: "tableName_ = %@ and owner_ = %@", dbObject.name, dbObject.owner))
    }
    
    
    var tableHeader: some View {
        HStack {
            VStack(alignment: .centreLine, spacing: 3) {
                FormField(label: "Partitioned?") {
                    Toggle("", isOn: .constant(tables.first?.isPartitioned ?? false))
                }
                FormField(label: "Row Count") {
                    Text(tables.first?.numRows.formatted() ?? Constants.nullValue)
                }
                
            }
            Spacer()
            VStack(alignment: .centreLine, spacing: 3) {
                FormField(label: "Last DDL") {
                    Text(dbObject.lastDDLDate?.ISO8601Format() ?? Constants.nullValue)
                }
                FormField(label: "Last Analyzed") {
                    Text(tables.first?.lastAnalyzed?.ISO8601Format() ?? Constants.nullValue)
                }
            }
            Spacer()
        }
            .padding()
    }
    
    var viewHeader: some View {
        HStack {
            VStack(alignment: .centreLine, spacing: 3) {
                FormField(label: "Editioning?") {
                    Toggle("", isOn: .constant(tables.first?.isEditioning ?? false))
                }
                FormField(label: "Read Only?") {
                    Toggle("", isOn: .constant(tables.first?.isEditioning ?? false))
                }
                
            }
            Spacer()
            VStack(alignment: .centreLine, spacing: 3) {
                FormField(label: "Last DDL") {
                    Text(dbObject.lastDDLDate?.ISO8601Format() ?? Constants.nullValue)
                }
            }
            Spacer()
        }
        .padding()
    }
    
    var body: some View {
        VStack {
            HStack {
                if tables.first?.isView ?? false {
                    Image(systemName: "tablecells.badge.ellipsis").foregroundColor(Color.blue)
                } else {
                    Image(systemName: "tablecells").foregroundColor(Color.blue)
                }
                Text("\(tables.first?.name ?? Constants.nullValue)")
                    .textSelection(.enabled)
                Spacer()
            }
            .font(.title)
            
            if tables.first?.isView ?? false { viewHeader } else { tableHeader }
            
            TabView(selection: $selectedTab) {
//                TableColumnsView(columns: Array(columns))
                DetailGridView(columns: Array(columns), columnLabels: columnLabels, booleanColumnLabels: booleanColumnLabels, columnSortFn: columnSortFn)
                    .tabItem {
                        Text("Columns")
                    }.tag("columns")
                
                if !(tables.first?.isView ?? false) {
                    TableIndexListView(dbObject: dbObject)
                        .tabItem {
                            Text("Indexes")
                        }.tag("indexes")
                    
                    Text("Table Constraints")
                        .tabItem {
                            Text("Constraints")
                        }.tag("constrains")

                    Text("Table DDL")
                        .tabItem {
                            Text("SQL")
                        }.tag("sql")

                }
                
                if tables.first?.isView ?? false {
                    VStack {
                        Button {
                            let formatter = Formatter()
                            var formattedSource = "...formatting, please wait..."
                            Task.init(priority: .background) { formattedSource = await formatter.formatSource(name: dbObject.name, text: tables.first?.sqltext) }
                            SwiftUIWindow.open {window in
                                let _ = (window.title = dbObject.name)
                                FormattedView(formattedSource: Binding(get: {formattedSource }, set: {_ in }) )
                            }
                             .clickable(true)
                            .mouseMovesWindow(true)
                        } label: { Text("Format Source") }
                        
                        CodeEditor(source: .constant(tables.first?.sqltext ?? "N/A"), language: .pgsql, theme: .atelierDuneLight, flags: [.selectable], autoscroll: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .tabItem {
                        Text("SQL")
                    }.tag("sql")
                }
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
