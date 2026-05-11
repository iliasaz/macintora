//
//  DBDetailInspectorView.swift
//  Macintora
//
//  Right-side `.inspector` companion for the object detail. Surfaces
//  statistics, storage, dependencies, privileges and comments without
//  consuming primary content area. Sections that have nothing to show
//  collapse silently — the inspector should not display empty "—" rows
//  just to look busy.
//

import SwiftUI
import CoreData

/// Dispatches to a type-specific inspector body. Returning `nil` when there's
/// nothing meaningful to show lets the parent collapse the inspector via
/// `.inspector(isPresented:)` rather than rendering an empty pane.
struct DBDetailInspectorView: View {
    @Binding var dbObject: DBCacheObject

    var body: some View {
        Form {
            Section("Object") {
                LabeledContent("Owner", value: dbObject.owner)
                LabeledContent("Object ID",
                               value: dbObject.objectId.formatted(.number.grouping(.never)))
                LabeledContent("Type",
                               value: (OracleObjectType(rawValue: dbObject.type) ?? .unknown).label)
                LabeledContent("Created",
                               value: dbObject.createDate?
                                .formatted(date: .abbreviated, time: .shortened) ?? Constants.nullValue)
                LabeledContent("Last DDL",
                               value: dbObject.lastDDLDate?
                                .formatted(date: .abbreviated, time: .shortened) ?? Constants.nullValue)
                LabeledContent("Valid") {
                    BoolIndicator(value: dbObject.isValid, trueColor: .green, falseColor: .red)
                }
            }

            switch OracleObjectType(rawValue: dbObject.type) {
            case .table, .view:
                DBTableInspectorSections(dbObject: $dbObject)
            default:
                EmptyView()
            }
        }
        .formStyle(.grouped)
    }
}

/// Statistics + storage rows pulled from `DBCacheTable`. Hidden when no
/// matching row exists yet (cache hasn't fetched details for this object).
struct DBTableInspectorSections: View {
    @Binding var dbObject: DBCacheObject
    @FetchRequest private var tables: FetchedResults<DBCacheTable>

    init(dbObject: Binding<DBCacheObject>) {
        self._dbObject = dbObject
        _tables = FetchRequest<DBCacheTable>(
            sortDescriptors: [],
            predicate: NSPredicate(format: "name_ = %@ and owner_ = %@",
                                   dbObject.name.wrappedValue, dbObject.owner.wrappedValue)
        )
    }

    var body: some View {
        if let tbl = tables.first {
            Section("Statistics") {
                LabeledContent("Rows", value: tbl.numRows.formatted())
                LabeledContent("Last Analyzed",
                               value: tbl.lastAnalyzed?
                                .formatted(date: .abbreviated, time: .shortened) ?? Constants.nullValue)
            }

            if !tbl.isView {
                Section("Storage") {
                    LabeledContent("Partitioned") {
                        BoolIndicator(value: tbl.isPartitioned)
                    }
                }
            } else {
                Section("View") {
                    LabeledContent("Editioning") {
                        BoolIndicator(value: tbl.isEditioning)
                    }
                    LabeledContent("Read Only") {
                        BoolIndicator(value: tbl.isReadOnly)
                    }
                }
            }
        }
    }
}
