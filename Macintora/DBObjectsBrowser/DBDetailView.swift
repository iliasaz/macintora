//
//  DBDetailView.swift
//  Macintora
//
//  Created by Ilia Sazonov on 8/31/22.
//

import SwiftUI

struct DBDetailObjectMainView: View {
    var dbObject: DBCacheObject
    var body: some View {
        VStack(alignment: .leading, spacing: 0.0) {
            Form {
                TextField("Object ID", value: Binding(get: { dbObject.objectId }, set: {_ in}) , format: .number.grouping(.never))
                TextField("Created", value: Binding(get: { dbObject.createDate} , set: {_ in}), format: .dateTime)
                TextField("Last DDL", value: Binding(get: { dbObject.lastDDLDate} , set: {_ in}), format: .dateTime)
                TextField("Edition", text: Binding(get: { dbObject.editionName ?? "" } , set: {_ in}))
                HStack {
                    Toggle("Editionable", isOn: Binding(get: { dbObject.isEditionable } , set: {_ in}))
                    Toggle("Valid", isOn: Binding(get: { dbObject.isValid } , set: {_ in}))
                }
            }
            .padding()
            .overlay(
                RoundedRectangle(cornerRadius: 25)
                    .stroke(.quaternary, lineWidth: 2)
            )
            .padding([.top, .leading, .trailing])
            Spacer()
        }
    }
}

struct DBDetailObjectDetailsView: View {
    var dbObject: DBCacheObject
    var body: some View {
        switch dbObject.type {
            case OracleObjectType.table.rawValue: DBTableDetailView(dbObject: dbObject)
            case OracleObjectType.view.rawValue: DBTableDetailView(dbObject: dbObject)
            case OracleObjectType.type.rawValue: DBSourceDetailView(dbObject: dbObject)
            case OracleObjectType.package.rawValue: DBSourceDetailView(dbObject: dbObject)
            case OracleObjectType.trigger.rawValue: DBTriggerDetailView(dbObject: dbObject)
            case OracleObjectType.procedure.rawValue: DBSourceDetailView(dbObject: dbObject)
            case OracleObjectType.function.rawValue: DBSourceDetailView(dbObject: dbObject)
            case OracleObjectType.index.rawValue: DBIndexDetailView(dbObject: dbObject)
            default: EmptyView()
        }
    }
}

struct DBDetailView: View {
    var dbObject: DBCacheObject
    @State private var selectedTab: String = "main"
    
    var body: some View {
        VStack(alignment: .leading) {
            DBDetailViewHeader(dbObject: dbObject)
                .padding([.top, .leading, .trailing])

            TabView {
                DBDetailObjectMainView(dbObject: dbObject)
                    .frame(alignment: .topLeading)
                    .tabItem {
                        Text("Main")
                    }
                    .tag("main")

                DBDetailObjectDetailsView(dbObject: dbObject)
                    .tabItem {
                        Text("Details")
                    }
                    .tag("details")
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
            try? cache.connectSvc()
            guard cache.isConnected == .connected else { isRefreshing = false; return }
            await cache.refreshObject(OracleObject(
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
                Label("Table", systemImage: "tablecells")
            case .view:
                Label("View", systemImage: "tablecells.badge.ellipsis")
            case .index:
                Label("Index", systemImage: "ecrease.indent")
            case .type:
                Label("Type", systemImage: "t.square")
            case .package:
                Label("Package", systemImage: "ellipsis.curlybraces")
            case .procedure:
                Label("Procedure", systemImage: "curlybraces")
            case .function:
                Label("Function", systemImage: "f.cursive")
            case .trigger:
                Label("Trigger", systemImage: "bolt")
            default:
                Label("Unknown", systemImage: "questionmark.square")
        }
    }
}



struct DBDetailView_Previews: PreviewProvider {
    static var previews: some View {
        DBDetailView(dbObject: DBCacheObject.exampleTrigger)
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
            .frame(width: 800, height: 800)
        DBDetailView(dbObject: DBCacheObject.exampleTable)
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
            .frame(width: 800, height: 800)
        DBDetailView(dbObject: DBCacheObject.examplePackage)
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
            .frame(width: 800, height: 800)
    }
}
