//
//  TableView.swift
//  MacOra
//
//  Created by Ilia on 12/15/21.
//

import SwiftUI
import CoreData

struct TableView: View {
    @Environment(\.managedObjectContext) var context
    @State private var selectedTab: String = "columns"
    @FetchRequest private var tables: FetchedResults<DBCacheTable>
    
    init(owner: String, name: String) {
        _tables = FetchRequest<DBCacheTable>(sortDescriptors: [], predicate: NSPredicate.init(format: "name_ = %@ and owner_ = %@", name, owner))
    }
    
    var body: some View {
            VStack {
                HStack {
                    Image(systemName: "tablecells").foregroundColor(Color.blue)
                    Text("\(tables.first?.name ?? "(null)")")
                    Spacer()
//                    Button {
//                        isTableSelected = false
//                        } label: { Image(systemName: "x.circle") }
                }
                .font(.title)
                HStack {
                    VStack (alignment: .trailing) {
                        Text("Owner")
                        Text("Row Count")
                    }
                    Spacer()
                    VStack {
                        Text("Partitioned?")
                        Text("Last Analyzed")
                    }
                }.padding(.horizontal)
                
                
                TabView(selection: $selectedTab) {
                    
//                    List {
//                        ForEach(Array(tables.first!.columns!), id: \.self) { col in
//                            Text(col.columnName_!)
//                        }
//
//                    }
                    Text("Columns")
                        .tabItem {
                            Text("Columns")
                        }.tag("columns")
                
                    
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
//            .onAppear() {
//                log("_tables: \(tables.count)")
//            }
    }
}

//struct TableColumnView: View {
//    @Binding var table: Table
//
//    var body: some View {
//        Table(table.has) {
//            TableColumn("Name", value: \.columnName_)
//        }
//    }
//}

//struct TableView_Previews: PreviewProvider {
//    static var previews: some View {
//        TableView()
//    }
//}
