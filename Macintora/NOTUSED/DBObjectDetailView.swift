//
//  TableView.swift
//  DBObjectsBrowser
//
//  Created by Ilia on 1/4/22.
//

import SwiftUI
import CoreData


struct DBObjectDetailView: View {
    @Environment(\.managedObjectContext) var context
    @State private var selectedTab: String = "columns"
    @FetchRequest private var tables: FetchedResults<DBCacheTable>
    @FetchRequest private var columns: FetchedResults<DBCacheTableColumn>
    
    init(owner: String, name: String) {
        _tables = FetchRequest<DBCacheTable>(sortDescriptors: [], predicate: NSPredicate.init(format: "name_ = %@ and owner_ = %@", name, owner))
        _columns = FetchRequest<DBCacheTableColumn>(sortDescriptors: [], predicate: NSPredicate.init(format: "tableName_ = %@ and owner_ = %@", name, owner))
    }
    
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "tablecells").foregroundColor(Color.blue)
                Text("\(tables.first?.name ?? Constants.nullValue)")
                Spacer()
            }
            .font(.title)
            HStack {
                VStack(alignment: .leading) {
                    Text("\(tables.first?.owner ?? Constants.nullValue)")
                    Text("\((tables.first?.partitioned ?? false) ? "Partitioned" : "Non-partitioned")")
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Analyzed on \(tables.first?.lastAnalyzed?.ISO8601Format() ?? Constants.nullValue)")
                    Text("Approx. \(tables.first?.numRows.formatted() ?? Constants.nullValue ) rows")
                }
            }.padding(.horizontal)
            
            
            TabView(selection: $selectedTab) {
                TableColumnsView(columns: Array(columns))
//                TableColumnsView(columns: tables.first?.columns ?? [DBCacheTableColumn]())
//                if let cols = tables.first?.columns {
//                    List (Array(cols as! Set<DBCacheTableColumn>), id: \.self) { (col: DBCacheTableColumn) in
//                        HStack {
//                            Text(col.columnName)
//                            Text(col.dataType)
//                        }
//                    }
                    .tabItem {
                        Text("Columns")
                    }.tag("columns")

//                } else { Text("No data available")
//
//                        .tabItem {
//                            Text("Columns")
//                        }.tag("columns")
//                }
                
                Text("Indexes")
                    .tabItem {
                        Text("Indexes")
                    }.tag("indexes")
                
                Text("Constraints")
                    .tabItem {
                        Text("Constraints")
                    }.tag("constrains")
                
                Text("SQL")
                    .tabItem {
                        Text("SQL")
                    }.tag("sql")
            }
            .font(.headline)
        }
        .frame(minWidth: 200, idealWidth: 400, maxWidth: .infinity)
        .padding()
    }
}

//struct TableView_Previews: PreviewProvider {
//    static var previews: some View {
//        var cache = DatabaseCache.preview
//        TableView(owner: "test", name: "test")
//            .environment(\.managedObjectContext, cache.persistentController.container.viewContext)
//    }
//}
