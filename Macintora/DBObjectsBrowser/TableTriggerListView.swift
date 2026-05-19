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
    @Binding var childSelection: DBChildSelection?
    @State private var selectedTriggerRow: DBCacheTrigger.ID?

    init(dbObject: DBCacheObject, childSelection: Binding<DBChildSelection?>) {
        self.dbObject = dbObject
        _triggers = FetchRequest<DBCacheTrigger>(sortDescriptors: [], predicate: NSPredicate.init(format: "objectName = %@ and objectOwner = %@", dbObject.name, dbObject.owner))
        _childSelection = childSelection
    }

    var body: some View {
        Table(triggers, selection: $selectedTriggerRow) {
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
        .onChange(of: selectedTriggerRow) { _, newID in
            childSelection = newID
                .flatMap { id in triggers.first { $0.id == id } }
                .map(DBChildSelection.trigger)
        }
    }
}
