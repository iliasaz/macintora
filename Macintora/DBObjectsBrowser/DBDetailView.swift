//
//  DBDetailView.swift
//  Macintora
//
//  Created by Ilia Sazonov on 8/31/22.
//

import SwiftUI

struct DBDetailView: View {
    var dbObject: DBCacheObject
    
    var body: some View {
        VStack {
            DBDetailViewHeader(dbObject: dbObject)
                .padding([.top, .leading, .trailing])
            ScrollView {
            Form {
                TextField("Object ID", value: .constant(dbObject.objectId), format: .number.grouping(.never))
                TextField("Created", value: .constant(dbObject.createDate), format: .dateTime)
                TextField("Last DDL", value: .constant(dbObject.lastDDLDate), format: .dateTime)
                TextField("Edition", text: .constant(dbObject.editionName ?? ""))
                HStack {
                    Toggle("Editionable", isOn: .constant(dbObject.isEditionable))
                    Toggle("Valid", isOn: .constant(dbObject.isValid))
                }
            }
            .padding()
            .overlay(
                RoundedRectangle(cornerRadius: 25)
                    .stroke(.quaternary, lineWidth: 2)
            )
            .padding([.top, .leading, .trailing])
            
            switch dbObject.type {
                case OracleObjectType.table.rawValue: DBTableDetailView(dbObject: dbObject)
                case OracleObjectType.view.rawValue: DBTableDetailView(dbObject: dbObject)
                case OracleObjectType.type.rawValue: DBSourceDetailView(dbObject: dbObject)
                case OracleObjectType.package.rawValue: DBSourceDetailView(dbObject: dbObject)
                case OracleObjectType.trigger.rawValue: DBTriggerDetailView(dbObject: dbObject)
                case OracleObjectType.index.rawValue: DBIndexDetailView(dbObject: dbObject)
                default: EmptyView()
            }
            }
        }
    }
}

struct DBDetailViewHeader: View {
    var dbObject: DBCacheObject
    @State private var isRefreshing = false
    @State private var isLoadingSource = false
    @EnvironmentObject private var cache: DBCacheVM
    
    var body: some View {
        HStack {
            DBDetailViewHeaderImage(type: OracleObjectType(rawValue: dbObject.type) ?? .unknown)
                .foregroundColor(Color.blue)
            Text("\(dbObject.name) (\(dbObject.owner))")
                .textSelection(.enabled)
            Spacer()
            
            // edit object source
            Button {
                guard !isLoadingSource else { return }
                Task(priority: .background) {
                    isLoadingSource = true
                    if let url = await cache.editSource(dbObject: dbObject) {
                        NSWorkspace.shared.open(url)
                    }
                    isLoadingSource = false
                }
            } label: {
                Image(systemName: "doc.circle").foregroundColor(.blue)
                    .rotationEffect(Angle.degrees(isLoadingSource ? 360 : 0))
                    .animation(.linear(duration: 2.0).repeat(while: isLoadingSource, autoreverses: false), value: isLoadingSource)
            }
                .buttonStyle(.borderless)
                .help("Edit")
            
            // refresh
            Button(action: refresh, label: {
                Image(systemName: "arrow.clockwise.circle").foregroundColor(.blue)
                    .rotationEffect(Angle.degrees(isRefreshing ? 360 : 0))
                    .animation(.linear(duration: 2.0).repeat(while: isRefreshing, autoreverses: false), value: isRefreshing)

            })
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
                .help("Refresh")
        }
            .font(.title)
    }
    
    func refresh() {
        Task(priority: .background) {
            isRefreshing = true
            try cache.connectSvc()
            await cache.refreshObject(obj: OracleObject(
                owner: dbObject.owner,
                name: dbObject.name,
                type: OracleObjectType(rawValue: dbObject.type) ?? .unknown,
                lastDDL: dbObject.lastDDLDate ?? Constants.minDate,
                createDate: dbObject.createDate ?? Constants.minDate,
                editionName: dbObject.editionName,
                isEditionable: dbObject.isEditionable,
                isValid: dbObject.isValid,
                objectId: dbObject.objectId
            )
            )
            cache.disconnectSvc()
            isRefreshing = false
        }
    }
}

struct DBDetailViewHeaderImage: View {
    var type: OracleObjectType
    
    var body: some View {
        switch type {
            case .table:
                Image(systemName: "tablecells")
            case .view:
                Image(systemName: "tablecells.badge.ellipsis")
            case .index:
                Image(systemName: "decrease.indent")
            case .type:
                Image(systemName: "t.square")
            case .package:
                Image(systemName: "ellipsis.curlybraces")
            case .trigger:
                Image(systemName: "bolt")
            default:
                Image(systemName: "questionmark.square")
        }
    }
}



struct DBDetailView_Previews: PreviewProvider {
    static var previews: some View {
        DBDetailView(dbObject: DBCacheObject.exampleTrigger)
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
            .frame(width: 800, height: 800)
    }
}
