//
//  DBTriggerDetailView.swift
//  Macintora
//
//  Created by Ilia Sazonov on 9/7/22.
//

import SwiftUI
import CoreData


struct DBTriggerDetailView: View {
    @Environment(\.managedObjectContext) var context
    @FetchRequest private var tables: FetchedResults<DBCacheTrigger>
    @Binding var dbObject: DBCacheObject

    init(dbObject: Binding<DBCacheObject>) {
        self._dbObject = dbObject
        _tables = FetchRequest<DBCacheTrigger>(sortDescriptors: [], predicate: NSPredicate.init(format: "name_ = %@ and owner_ = %@ ", dbObject.name.wrappedValue, dbObject.owner.wrappedValue))
    }

    private var triggerForm: some View {
        let trigger = tables.first
        return Form {
            Section("Trigger Details") {
                LabeledContent("Type", value: trigger?.type ?? Constants.nullValue)
                LabeledContent("When", value: trigger?.whenClause ?? Constants.nullValue)
                LabeledContent("Column", value: trigger?.columnName ?? Constants.nullValue)
                LabeledContent("Base Type", value: trigger?.objectType ?? Constants.nullValue)
                LabeledContent("Base Owner", value: trigger?.objectOwner ?? Constants.nullValue)
                LabeledContent("Base Name", value: trigger?.objectName ?? Constants.nullValue)
                LabeledContent("Referencing", value: trigger?.referencingNames ?? Constants.nullValue)
                LabeledContent("Description", value: trigger?.descr ?? Constants.nullValue)
            }

            Section("Timing") {
                LabeledContent("Before Row") { BoolIndicator(value: trigger?.isBeforeRow ?? false) }
                LabeledContent("After Row") { BoolIndicator(value: trigger?.isAfterRow ?? false) }
                LabeledContent("Before Statement") { BoolIndicator(value: trigger?.isBeforeStatement ?? false) }
                LabeledContent("After Statement") { BoolIndicator(value: trigger?.isAfterStatement ?? false) }
                LabeledContent("Instead Of") { BoolIndicator(value: trigger?.isInsteadOfRow ?? false) }
                LabeledContent("CrossEdition") { BoolIndicator(value: trigger?.isCrossEdition ?? false) }
                LabeledContent("Fire Once") { BoolIndicator(value: trigger?.isFireOnce ?? false) }
                LabeledContent("Enabled") { BoolIndicator(value: trigger?.isEnabled ?? false, trueColor: .green, falseColor: .red) }
            }
        }
        .formStyle(.grouped)
    }

    var body: some View {
        VStack(alignment: .leading) {
            triggerForm
            SourceView(objName: $dbObject.name, text: Binding<String>(get: {tables.first?.body ?? ""}, set: {_ in}), title: "Body")
        }
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
