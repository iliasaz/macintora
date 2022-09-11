//
//  TableTriggerListView.swift
//  Macintora
//
//  Created by Ilia Sazonov on 9/10/22.
//

import SwiftUI
import CoreData
import SwiftOracle

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
                Toggle("", isOn: Binding(get: {value.isEnabled}, set: {_ in }))
                    .toggleStyle(.checkbox)
            }
            TableColumn("Type", value: \.type )
            TableColumn("Action Type", value: \.actionType )
            TableColumn("Event", value: \.event )
        }
        .font(Font(NSFont(name: "Source Code Pro", size: NSFont.systemFontSize)!))
    }
    
}

//struct TableIndexListView_Previews: PreviewProvider {
//    static var previews: some View {
//        TableIndexListView()
//    }
//}

