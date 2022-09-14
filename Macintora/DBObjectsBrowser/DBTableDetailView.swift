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
                FormField(label: "Last Analyzed") {
                    Text(tables.first?.lastAnalyzed?.ISO8601Format() ?? Constants.nullValue)
                }
            }
            Spacer()
        }
        .padding()
        .overlay(
            RoundedRectangle(cornerRadius: 25)
                .stroke(.quaternary, lineWidth: 2)
        )
    }
    
    var viewHeader: some View {
        HStack {
            VStack(alignment: .centreLine, spacing: 3) {
                FormField(label: "Editioning?") {
                    Toggle("", isOn: .constant(tables.first?.isEditioning ?? false))
                }
                FormField(label: "Read Only?") {
                    Toggle("", isOn: .constant(tables.first?.isReadOnly ?? false))
                }
                
            }
            Spacer()
        }
        .padding()
        .overlay(
            RoundedRectangle(cornerRadius: 25)
                .stroke(.quaternary, lineWidth: 2)
        )
    }
    
    var body: some View {
        VStack {
            if tables.first?.isView ?? false { viewHeader } else { tableHeader }
            
            TabView(selection: $selectedTab) {
                DetailGridView(rows: Array(columns), columnLabels: columnLabels, booleanColumnLabels: booleanColumnLabels, rowSortFn: columnSortFn)
                    .frame(maxWidth: .infinity, minHeight: 100, idealHeight: 300, maxHeight: .infinity, alignment: .topLeading)
                    .tabItem {
                        Text("Columns")
                    }.tag("columns")
                
                if !(tables.first?.isView ?? false) {
                    TableIndexListView(dbObject: dbObject)
                        .frame(maxWidth: .infinity, minHeight: 100, idealHeight: 300, maxHeight: .infinity, alignment: .topLeading)
                        .tabItem {
                            Text("Indexes")
                        }.tag("indexes")
                    
                    TableTriggerListView(dbObject: dbObject)
                        .frame(maxWidth: .infinity, minHeight: 100, idealHeight: 300, maxHeight: .infinity, alignment: .topLeading)
                        .tabItem {
                            Text("Triggers")
                        }.tag("triggers")

//                    Text("Table DDL")
//                        .tabItem {
//                            Text("SQL")
//                        }.tag("sql")

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
                            .closeOnEscape(true)
                        } label: { Text("Format Source") }
                        
                        CodeEditor(source: .constant(tables.first?.sqltext ?? "N/A"), language: .pgsql, theme: .atelierDuneLight, flags: [.selectable], autoscroll: false)
                            .frame(maxWidth: .infinity, minHeight: 100, idealHeight: 300, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .tabItem {
                        Text("SQL")
                    }.tag("sql")
                }
            }
            .font(.headline)
        }
//        .frame(minWidth: 200, idealWidth: 400, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
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
