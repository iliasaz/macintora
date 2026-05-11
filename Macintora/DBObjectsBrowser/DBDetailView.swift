//
//  DBDetailView.swift
//  Macintora
//
//  Created by Ilia Sazonov on 8/31/22.
//

import SwiftUI
import os

/// Top-level tab selection for `DBDetailView`.
/// Codable so it round-trips through `DBCacheInputValue` for scene restoration.
enum DBDetailTab: String, Codable, Hashable, CaseIterable, Sendable {
    case main
    case details
}

struct DBDetailObjectMainView: View {
    @Binding var dbObject: DBCacheObject

    private var hasProcedureContent: Bool {
        switch dbObject.type {
        case OracleObjectType.package.rawValue,
             OracleObjectType.procedure.rawValue,
             OracleObjectType.function.rawValue:
            return true
        default:
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0.0) {
            Form {
                LabeledContent("Object ID", value: dbObject.objectId.formatted(.number.grouping(.never)))
                LabeledContent("Created", value: dbObject.createDate?.formatted(date: .abbreviated, time: .standard) ?? Constants.nullValue)
                LabeledContent("Last DDL", value: dbObject.lastDDLDate?.formatted(date: .abbreviated, time: .standard) ?? Constants.nullValue)
                LabeledContent("Edition", value: dbObject.editionName ?? Constants.nullValue)
                LabeledContent("Editionable") {
                    BoolIndicator(value: dbObject.isEditionable)
                }
                LabeledContent("Valid") {
                    BoolIndicator(value: dbObject.isValid, trueColor: .green, falseColor: .red)
                }
            }
            .formStyle(.grouped)

            if hasProcedureContent {
                PackageProceduresListView(dbObject: dbObject)
            } else {
                Spacer()
            }
        }
    }
}

struct DBDetailObjectDetailsView: View {
    @Binding var dbObject: DBCacheObject
    var body: some View {
        switch dbObject.type {
            case OracleObjectType.table.rawValue: DBTableDetailView(dbObject: $dbObject)
            case OracleObjectType.view.rawValue: DBTableDetailView(dbObject: $dbObject)
            case OracleObjectType.type.rawValue: DBSourceDetailView(dbObject: $dbObject)
            case OracleObjectType.package.rawValue: DBSourceDetailView(dbObject: $dbObject)
            case OracleObjectType.trigger.rawValue: DBTriggerDetailView(dbObject: $dbObject)
            case OracleObjectType.procedure.rawValue: DBSourceDetailView(dbObject: $dbObject)
            case OracleObjectType.function.rawValue: DBSourceDetailView(dbObject: $dbObject)
            case OracleObjectType.index.rawValue: DBIndexDetailView(dbObject: $dbObject)
            default: EmptyView()
        }
    }
}

struct DBDetailView: View {
    @Binding var dbObject: DBCacheObject
    @EnvironmentObject private var cache: DBCacheVM
    @AppStorage("dbDetailSelectedTab") private var selectedTab: DBDetailTab = .details
    @State private var hasAppliedInitialTab = false

    var body: some View {
        VStack(alignment: .leading) {
            DBDetailViewHeader(dbObject: $dbObject)
                .padding([.top, .leading, .trailing])

            TabView(selection: $selectedTab) {
                Tab("Main", systemImage: "info.circle", value: DBDetailTab.main) {
                    DBDetailObjectMainView(dbObject: $dbObject)
                        .frame(alignment: .topLeading)
                }

                Tab("Details", systemImage: "list.bullet.rectangle", value: DBDetailTab.details) {
                    DBDetailObjectDetailsView(dbObject: $dbObject)
                }
            }
        }
        .onAppear {
            guard !hasAppliedInitialTab else { return }
            hasAppliedInitialTab = true
            if let tab = cache.initialDetailTab {
                selectedTab = tab
                cache.initialDetailTab = nil
            }
        }
    }
}

struct DBDetailViewHeader: View {
    @Binding var dbObject: DBCacheObject
    @State private var isRefreshing = false
    @State private var isLoadingSource = false
    @EnvironmentObject private var cache: DBCacheVM

    var body: some View {
        HStack(spacing: 8) {
            DBDetailViewHeaderImage(type: Binding( get: { OracleObjectType(rawValue: dbObject.type) ?? .unknown}, set: {_ in }))
                .labelStyle(.titleAndIcon)
                .font(.title3)
            Text("\(dbObject.name) (\(dbObject.owner))")
                .textSelection(.enabled)
                .font(.title3)
                .bold()
            Spacer()

            Button("Edit Source", systemImage: "square.and.pencil") {
                guard !isLoadingSource else { return }
                Task(priority: .background) {
                    isLoadingSource = true
                    if let url = await cache.editSource(dbObject: dbObject) {
                        NSWorkspace.shared.open(url)
                    }
                    isLoadingSource = false
                }
            }
            .buttonStyle(.borderless)
            .disabled(isLoadingSource)
            .help("Open source in editor")

            if isLoadingSource {
                ProgressView().controlSize(.small)
            }

            Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
                .help("Refresh this object")

            if isRefreshing {
                ProgressView().controlSize(.small)
            }
        }
    }

    func refresh() {
        Task(priority: .background) {
            await MainActor.run { isRefreshing = true }
            do {
                try await cache.connectSvc()
                await MainActor.run { cache.isConnected = .connected }
            } catch {
                log.cache.error("not connected")
                await MainActor.run { isRefreshing = false}
                return
            }
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
            ))
            await cache.disconnectSvc()
            await MainActor.run { isRefreshing = false}
        }
    }
}

struct DBDetailViewHeaderImage: View {
    @Binding var type: OracleObjectType

    var body: some View {
        switch type {
            case .table:
                Label("Table", systemImage: "tablecells")
            case .view:
                Label("View", systemImage: "tablecells.badge.ellipsis")
            case .index:
                Label("Index", systemImage: "list.bullet.indent")
            case .type:
                Label("Type", systemImage: "shippingbox")
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

/// Non-interactive boolean presenter for read-only fields. Replaces
/// `Toggle(isOn: .constant(...))`, which renders an interactive-looking
/// switch that doesn't actually toggle.
struct BoolIndicator: View {
    let value: Bool
    var trueColor: Color = .accentColor
    var falseColor: Color = .secondary

    var body: some View {
        Image(systemName: value ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(value ? trueColor : falseColor)
            .accessibilityLabel(value ? "Yes" : "No")
    }
}

struct DBDetailView_Previews: PreviewProvider {
    static var previews: some View {
        DBDetailView(dbObject: .constant(DBCacheObject.exampleTrigger))
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
            .frame(width: 800, height: 800)
        DBDetailView(dbObject: .constant(DBCacheObject.exampleTable))
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
            .frame(width: 800, height: 800)
        DBDetailView(dbObject: .constant(DBCacheObject.examplePackage))
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
            .frame(width: 800, height: 800)
    }
}
