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
    @Binding var dbObject: DBCacheObject
    
    let columnLabels = ["columnID", "columnName", "dataType", "dataTypeMod", "dataTypeOwner", "length", "precision", "scale", "isNullable", "numNulls", "numDistinct", "isIdentity", "isHidden", "isVirtual", "isSysGen", "defaultValue","internalColumnID", ]
    let booleanColumnLabels = ["isNullable", "isHidden", "isIdentity", "isSysGen", "isVirtual"]
    var columnSortFn = { (lhs: NSManagedObject, rhs: NSManagedObject) in (lhs as! DBCacheTableColumn).internalColumnID < (rhs as! DBCacheTableColumn).internalColumnID }

    init(dbObject: Binding<DBCacheObject>) {
        self._dbObject = dbObject
        _tables = FetchRequest<DBCacheTable>(sortDescriptors: [], predicate: NSPredicate.init(format: "name_ = %@ and owner_ = %@", dbObject.name.wrappedValue, dbObject.owner.wrappedValue))
        _columns = FetchRequest<DBCacheTableColumn>(sortDescriptors: [], predicate: NSPredicate.init(format: "tableName_ = %@ and owner_ = %@", dbObject.name.wrappedValue, dbObject.owner.wrappedValue))
    }
    
    var sqlText: String { tables.first?.sqltext ?? "" }
    
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
                DetailGridView(rows: Binding(get: { Array(columns)}, set: { _ in }), columnLabels: columnLabels, booleanColumnLabels: booleanColumnLabels, rowSortFn: columnSortFn)
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
                }
                
                if tables.first?.isView ?? false {
                    VStack {
                        Button {
                            let formatter = Formatter()
                            formatter.formattedSource = "...formatting, please wait..."
                            
                            SwiftUIWindow.open {window in
                                let _ = (window.title = dbObject.name)
                                FormattedView(formatter: formatter)
                            }
                            .closeOnEscape(true)
                            
                            formatter.formatSource(name: dbObject.name, text: tables.first?.sqltext)
                            
                        } label: { Text("Format Source") }
                        
//                        CodeEditor(source: .constant(tables.first?.sqltext ?? "N/A"), language: .pgsql, theme: .atelierDuneLight, flags: [.selectable], autoscroll: false, wordWrap: .constant(true))
                        Text("\(sqlText)")
                            .monospaced()
                            .textSelection(.enabled)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 100, idealHeight: 300, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .tabItem {
                        Text("SQL")
                    }.tag("sql")
                }
            }
        }
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
