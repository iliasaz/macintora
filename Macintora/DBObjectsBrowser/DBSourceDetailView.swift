//
//  DBSourceDetailView.swift
//  DBObjectsBrowser
//
//  Created by Ilia on 1/4/22.
//

import SwiftUI
import CoreData

private enum DBSourceTab: String, CaseIterable, Codable {
    case spec
    case body
}

struct DBSourceDetailView: View {
    @Environment(\.managedObjectContext) var context
    @AppStorage("dbSourceDetailSelectedTab") private var selectedTab: DBSourceTab = .spec
    @FetchRequest private var tables: FetchedResults<DBCacheSource>
    @Binding var dbObject: DBCacheObject

    init(dbObject: Binding<DBCacheObject>) {
        self._dbObject = dbObject
        _tables = FetchRequest<DBCacheSource>(sortDescriptors: [], predicate: NSPredicate.init(format: "name_ = %@ and owner_ = %@ ", dbObject.name.wrappedValue, dbObject.owner.wrappedValue))
    }

    var textSpec: Binding<String> { Binding<String>( get: { tables.first?.textSpec ?? "" }, set: {_ in} ) }
    var textBody: Binding<String> { Binding<String>( get: { tables.first?.textBody ?? "" }, set: {_ in} ) }

    var body: some View {
        VStack(alignment: .leading) {
            TabView(selection: $selectedTab) {
                Tab("Spec", systemImage: "doc.text", value: DBSourceTab.spec) {
                    SourceView(objName: $dbObject.name, text: textSpec, title: "Specification")
                        .padding(.vertical, 5)
                }
                Tab("Body", systemImage: "doc.text.fill", value: DBSourceTab.body) {
                    SourceView(objName: $dbObject.name, text: textBody, title: "Body")
                        .padding(.vertical, 5)
                }
            }
        }
        .frame(minWidth: 200, idealWidth: 1000, maxWidth: .infinity, idealHeight: 1000, maxHeight: .infinity)
        .padding()
    }
}
