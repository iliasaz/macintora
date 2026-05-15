//
//  DBTriggerDetailView.swift
//  Macintora
//
//  Created by Ilia Sazonov on 9/7/22.
//

import SwiftUI
import CoreData

private enum DBTriggerTab: String, CaseIterable, Codable {
    case body
}

struct DBTriggerDetailView: View {
    @Environment(\.managedObjectContext) var context
    @AppStorage("dbTriggerDetailSelectedTab") private var selectedTab: DBTriggerTab = .body
    @FetchRequest private var triggers: FetchedResults<DBCacheTrigger>
    @Binding var dbObject: DBCacheObject

    init(dbObject: Binding<DBCacheObject>) {
        self._dbObject = dbObject
        _triggers = FetchRequest<DBCacheTrigger>(
            sortDescriptors: [],
            predicate: NSPredicate(format: "name_ = %@ and owner_ = %@",
                                   dbObject.name.wrappedValue,
                                   dbObject.owner.wrappedValue)
        )
    }

    private var bodyText: Binding<String> {
        Binding<String>(get: { triggers.first?.body ?? "" }, set: { _ in })
    }

    var body: some View {
        VStack(alignment: .leading) {
            TabView(selection: $selectedTab) {
                Tab("Body", systemImage: "doc.text.fill", value: DBTriggerTab.body) {
                    SourceView(objName: $dbObject.name, text: bodyText, title: "Body")
                        .padding(.vertical, 5)
                }
            }
        }
        .frame(minWidth: 200, idealWidth: 1000, maxWidth: .infinity,
               idealHeight: 1000, maxHeight: .infinity)
        .padding()
    }
}

struct DBTriggerDetailView_Previews: PreviewProvider {
    static var previews: some View {
        DBTriggerDetailView(dbObject: .constant(DBCacheObject.exampleTrigger))
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
            .frame(width: 800, height: 800)
    }
}
