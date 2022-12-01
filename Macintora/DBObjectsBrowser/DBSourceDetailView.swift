//
//  DBSourceDetailView.swift
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
    @ObservedObject var dbObject: DBCacheObject
    {
        mutating didSet {
            _tables = FetchRequest<DBCacheSource>(sortDescriptors: [], predicate: NSPredicate.init(format: "name_ = %@ and owner_ = %@ ", dbObject.name, dbObject.owner))
        }
    }
    
    init(dbObject: DBCacheObject) {
        self.dbObject = dbObject
        _tables = FetchRequest<DBCacheSource>(sortDescriptors: [], predicate: NSPredicate.init(format: "name_ = %@ and owner_ = %@ ", dbObject.name, dbObject.owner))
    }
    
    var tableHeader: some View {
        EmptyView()
            .padding()
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            tableHeader
            VSplitView {
                SourceView(objName: $dbObject.name, text: Binding<String?>(get: {tables.first?.textSpec ?? ""}, set: {_ in}), title: "Specification")
                    .padding(.vertical,5)
                SourceView(objName: $dbObject.name, text: Binding<String?>(get: {tables.first?.textBody ?? ""}, set: {_ in}), title: "Body")
                    .padding(.vertical,5)
            }
        }
        .frame(minWidth: 200, idealWidth: 1000, maxWidth: .infinity, idealHeight: 1000, maxHeight: .infinity)
        .padding()
    }
}


