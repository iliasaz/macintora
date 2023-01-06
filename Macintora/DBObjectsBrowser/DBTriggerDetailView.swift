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
    
    var tableHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Trigger Details") {
                    TextField("Type", text: .constant(tables.first?.type ?? ""))
                    TextField("When", text: .constant(tables.first?.whenClause ?? ""))
                    TextField("Column", text: .constant(tables.first?.columnName ?? ""))
                    TextField("Base Type", text: .constant(tables.first?.objectType ?? ""))
                    TextField("Base Owner", text: .constant(tables.first?.objectOwner ?? ""))
                    TextField("Base Name", text: .constant(tables.first?.objectName ?? ""))
                    TextField("Referencing", text: .constant(tables.first?.referencingNames ?? ""))
                    TextField("Description", text: .constant(tables.first?.descr ?? ""))
                }
                        
                Section("") {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading) {
                            Toggle("Before Row", isOn: .constant(tables.first?.isBeforeRow ?? false))
                            Toggle("Ater Row", isOn: .constant(tables.first?.isAfterRow ?? false))
                            Toggle("CrossEdition", isOn: .constant(tables.first?.isCrossEdition ?? false))
                            Toggle("Fire Once", isOn: .constant(tables.first?.isFireOnce ?? false))
                        }
                        VStack(alignment: .leading) {
                            Toggle("Before Statement", isOn: .constant(tables.first?.isBeforeStatement ?? false))
                            Toggle("Ater Statement", isOn: .constant(tables.first?.isAfterStatement ?? false))
                            Toggle("Instead Of", isOn: .constant(tables.first?.isInsteadOfRow ?? false))
                            Toggle("Enabled", isOn: .constant(tables.first?.isEnabled ?? false))
                        }
                    }
                }
            }
            .padding()
            .overlay(
                RoundedRectangle(cornerRadius: 25)
                    .stroke(.quaternary, lineWidth: 2)
            )
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            tableHeader
            
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
