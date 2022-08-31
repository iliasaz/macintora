//
//  TableView.swift
//  DBObjectsBrowser
//
//  Created by Ilia on 1/4/22.
//

import SwiftUI
import CoreData
import CodeEditor

struct DBSourceDetailView: View {
    @Environment(\.managedObjectContext) var context
    @FetchRequest private var tables: FetchedResults<DBCacheSource>
    private var dbObject: DBCacheObject
    
    init(dbObject: DBCacheObject) {
        self.dbObject = dbObject
        _tables = FetchRequest<DBCacheSource>(sortDescriptors: [], predicate: NSPredicate.init(format: "name_ = %@ and owner_ = %@ ", dbObject.name, dbObject.owner))
    }
    
    var tableHeader: some View {
        HStack {
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
        VStack(alignment: .leading) {
            HStack {
                if dbObject.type == OracleObjectType.type.rawValue {
                    Image(systemName: "t.square").foregroundColor(Color.blue)
                } else if dbObject.type == OracleObjectType.package.rawValue {
                    Image(systemName: "curlybraces.square").foregroundColor(Color.blue)
                } else {
                    Image(systemName: "questionmark.square").foregroundColor(Color.blue)
                }
                Text("\(tables.first?.name ?? Constants.nullValue)")
                    .textSelection(.enabled)
                Spacer()
            }
            .font(.title)
            
            tableHeader
            
            SourceView(objName: dbObject.name, text: tables.first?.textSpec, title: "Specification")
            SourceView(objName: dbObject.name, text: tables.first?.textBody, title: "Body")

        }
        .frame(minWidth: 200, idealWidth: 1000, maxWidth: .infinity)
        .padding()
    }
}

struct SourceView: View {
    @State var objName: String
    @State var text: String?
    @State var title: String
    
    var body: some View {
        VStack {
            HStack {
                Text(title)
                    .font(.title2)
                    .frame(alignment:.leading)
                Spacer()
                Button {
                    let formatter = Formatter()
                    var formattedSource = "...formatting, please wait..."
                    Task.init(priority: .background) { formattedSource = await formatter.formatSource(name: objName, text: text) }
                    SwiftUIWindow.open {window in
                        let _ = (window.title = objName)
                        FormattedView(formattedSource: Binding(get: {formattedSource }, set: {_ in }) )
                    }
                    .clickable(true)
                    .mouseMovesWindow(true)
                }
            label: { Text("Format Source") }
            }
            CodeEditor(source: .constant(text ?? "N/A"), language: .pgsql, theme: .atelierDuneLight, flags: [.selectable], autoscroll: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
}
