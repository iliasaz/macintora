//
//  TableTriggerListView.swift
//  Macintora
//
//  Created by Ilia Sazonov on 9/10/22.
//

import SwiftUI
import CoreData

struct TableTriggerListView: View {
    @Environment(\.managedObjectContext) var context
    @FetchRequest private var triggers: FetchedResults<DBCacheTrigger>
    private var dbObject: DBCacheObject
    @State private var selectedIndexRow: DBCacheTrigger.ID?


    init(dbObject: DBCacheObject) {
        self.dbObject = dbObject
        _triggers = FetchRequest<DBCacheTrigger>(sortDescriptors: [], predicate: NSPredicate.init(format: "objectName = %@ and objectOwner = %@", dbObject.name, dbObject.owner))
    }

    var body: some View {
        Table(triggers, selection: $selectedIndexRow) {
            TableColumn("Trigger Name", value: \.name )
            TableColumn("Trigger Owner", value: \.owner )
            TableColumn("Enabled?") { value in
                BoolIndicator(value: value.isEnabled, trueColor: .green, falseColor: .red)
            }
            TableColumn("Type", value: \.type )
            TableColumn("Action Type", value: \.actionType )
            TableColumn("Event", value: \.event )
        }
        .font(.system(.body, design: .monospaced))
    }

}

//struct TableIndexListView_Previews: PreviewProvider {
//    static var previews: some View {
//        TableIndexListView()
//    }
//}
