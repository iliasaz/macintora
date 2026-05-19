//
//  DBDetailInspectorView.swift
//  Macintora
//
//  Right-side inspector companion for the object detail. Dispatches:
//   - child selected in a sub-tab (column/index/trigger) → child-specific
//     inspector body
//   - else → object-level inspector (general + type-specific sections)
//  Sections with nothing to show stay collapsed silently.
//

import SwiftUI
import CoreData

struct DBDetailInspectorView: View {
    @Binding var dbObject: DBCacheObject
    @Binding var childSelection: DBChildSelection?

    var body: some View {
        switch childSelection {
        case .column(let c):
            ColumnInspector(column: c)
        case .index(let i):
            IndexInspector(index: i)
        case .trigger(let t):
            TriggerInspector(trigger: t)
        case .none:
            ObjectInspector(dbObject: $dbObject)
        }
    }
}

// MARK: - Object-level inspector

private struct ObjectInspector: View {
    @Binding var dbObject: DBCacheObject

    var body: some View {
        Form {
            Section("Identification") {
                LabeledContent("Owner", value: dbObject.owner)
                LabeledContent("Name", value: dbObject.name)
                LabeledContent("Type",
                               value: (OracleObjectType(rawValue: dbObject.type) ?? .unknown).label)
                LabeledContent("Object ID",
                               value: dbObject.objectId.formatted(.number.grouping(.never)))
            }

            Section("Lifecycle") {
                LabeledContent("Created",
                               value: dbObject.createDate?
                                .formatted(date: .abbreviated, time: .shortened) ?? Constants.nullValue)
                LabeledContent("Last DDL",
                               value: dbObject.lastDDLDate?
                                .formatted(date: .abbreviated, time: .shortened) ?? Constants.nullValue)
                LabeledContent("Edition", value: dbObject.editionName ?? Constants.nullValue)
                LabeledContent("Editionable", value: dbObject.isEditionable ? "Yes" : "No")
                LabeledContent("Valid") {
                    BoolIndicator(value: dbObject.isValid, trueColor: .green, falseColor: .red)
                }
            }

            switch OracleObjectType(rawValue: dbObject.type) {
            case .table, .view:
                DBTableInspectorSections(dbObject: $dbObject)
            case .trigger:
                DBTriggerLookupSections(name: dbObject.name, owner: dbObject.owner)
            case .index:
                DBIndexLookupSections(name: dbObject.name, owner: dbObject.owner)
            default:
                EmptyView()
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Column-level inspector

private struct ColumnInspector: View {
    let column: DBCacheTableColumn

    var body: some View {
        Form {
            Section("Identification") {
                LabeledContent("Column ID", value: (column.columnID as? Int)?.formatted() ?? "")
                LabeledContent("Internal ID", value: column.internalColumnID.formatted())
                LabeledContent("Column Name", value: column.columnName)
            }

            Section("Type") {
                LabeledContent("Datatype", value: column.dataType)
                LabeledContent("Datatype Owner", value: column.dataTypeOwner)
                LabeledContent("Length", value: column.length.formatted())
                LabeledContent("Precision", value: (column.precision as? Int)?.formatted() ?? "")
                LabeledContent("Scale", value: (column.scale as? Int)?.formatted() ?? "")
            }

            Section("Nulls") {
                LabeledContent("Nullable", value: column.isNullable ? "Yes" : "No")
                LabeledContent("Nulls", value: column.numNulls.formatted())
                LabeledContent("Distinct", value: column.numDistinct.formatted())
            }

            Section("Attributes") {
                LabeledContent("Identity", value: column.isIdentity ? "Yes" : "No")
                LabeledContent("Hidden", value: column.isHidden ? "Yes" : "No")
                LabeledContent("Virtual", value: column.isVirtual ? "Yes" : "No")
                LabeledContent("Sys Gen", value: column.isSysGen ? "Yes" : "No")
            }

            Section("Default") {
                Text(column.defaultValue ?? "")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(nil)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Index-level inspector

private struct IndexInspector: View {
    let index: DBCacheIndex

    var body: some View {
        Form {
            Section("Identification") {
                LabeledContent("Owner", value: index.owner)
                LabeledContent("Name", value: index.name)
                LabeledContent("Type", value: index.type)
                LabeledContent("Tablespace", value: index.tablespaceName)
                LabeledContent("Degree", value: index.degree)
            }

            Section("Table") {
                LabeledContent("Owner", value: index.tableOwner)
                LabeledContent("Name", value: index.tableName)
            }

            Section("Statistics") {
                LabeledContent("Rows", value: index.numRows.formatted())
                LabeledContent("Distinct Keys", value: index.distinctKeys.formatted())
                LabeledContent("Leaf Blocks", value: index.leafBlocks.formatted())
                LabeledContent("Clustering Factor", value: index.clusteringFactor.formatted())
                LabeledContent("Avg Leaf / Key", value: index.avgLeafBlocksPerKey.formatted(.number.precision(.fractionLength(2))))
                LabeledContent("Avg Data / Key", value: index.avgDataBlocksPerKey.formatted(.number.precision(.fractionLength(2))))
                LabeledContent("Sample Size", value: index.sampleSize.formatted())
                LabeledContent("Last Analyzed",
                               value: index.lastAnalyzed?
                                .formatted(date: .abbreviated, time: .shortened) ?? Constants.nullValue)
            }

            Section("Attributes") {
                LabeledContent("Unique") { BoolIndicator(value: index.isUnique) }
                LabeledContent("Visible") { BoolIndicator(value: index.isVisible) }
                LabeledContent("Partitioned") { BoolIndicator(value: index.isPartitioned) }
                LabeledContent("Valid") {
                    BoolIndicator(value: index.isValid, trueColor: .green, falseColor: .red)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Trigger-level inspector

private struct TriggerInspector: View {
    let trigger: DBCacheTrigger

    var body: some View {
        Form {
            Section("Identification") {
                LabeledContent("Owner", value: trigger.owner)
                LabeledContent("Name", value: trigger.name)
                LabeledContent("Type", value: trigger.type)
                LabeledContent("Action Type", value: trigger.actionType)
                LabeledContent("Event", value: trigger.event)
            }

            Section("Trigger") {
                LabeledContent("When", value: trigger.whenClause ?? Constants.nullValue)
                LabeledContent("Column", value: trigger.columnName ?? Constants.nullValue)
                LabeledContent("Referencing", value: trigger.referencingNames ?? Constants.nullValue)
                LabeledContent("Description", value: trigger.descr ?? Constants.nullValue)
            }

            Section("Base Object") {
                LabeledContent("Type", value: trigger.objectType)
                LabeledContent("Owner", value: trigger.objectOwner ?? Constants.nullValue)
                LabeledContent("Name", value: trigger.objectName ?? Constants.nullValue)
            }

            Section("Firing") {
                LabeledContent("Before Row") { BoolIndicator(value: trigger.isBeforeRow) }
                LabeledContent("After Row") { BoolIndicator(value: trigger.isAfterRow) }
                LabeledContent("Before Statement") { BoolIndicator(value: trigger.isBeforeStatement) }
                LabeledContent("After Statement") { BoolIndicator(value: trigger.isAfterStatement) }
                LabeledContent("Instead Of") { BoolIndicator(value: trigger.isInsteadOfRow) }
                LabeledContent("Cross Edition") { BoolIndicator(value: trigger.isCrossEdition) }
                LabeledContent("Fire Once") { BoolIndicator(value: trigger.isFireOnce) }
                LabeledContent("Enabled") {
                    BoolIndicator(value: trigger.isEnabled, trueColor: .green, falseColor: .red)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Type-specific sections for ObjectInspector

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

/// When the sidebar selection is an Index object directly (not a child row
/// of a table), look it up by name+owner and surface the same fields as
/// `IndexInspector`.
private struct DBIndexLookupSections: View {
    @FetchRequest private var indexes: FetchedResults<DBCacheIndex>

    init(name: String, owner: String) {
        _indexes = FetchRequest<DBCacheIndex>(
            sortDescriptors: [],
            predicate: NSPredicate(format: "name_ = %@ and owner_ = %@", name, owner)
        )
    }

    var body: some View {
        if let idx = indexes.first {
            Section("Statistics") {
                LabeledContent("Rows", value: idx.numRows.formatted())
                LabeledContent("Last Analyzed",
                               value: idx.lastAnalyzed?
                                .formatted(date: .abbreviated, time: .shortened) ?? Constants.nullValue)
            }
            Section("Attributes") {
                LabeledContent("Partitioned") { BoolIndicator(value: idx.isPartitioned) }
                LabeledContent("Unique") { BoolIndicator(value: idx.isUnique) }
                LabeledContent("Visible") { BoolIndicator(value: idx.isVisible) }
            }
        }
    }
}

/// When the sidebar selection is a Trigger object directly (not a child row
/// of a table), look it up by name+owner and surface key fields.
private struct DBTriggerLookupSections: View {
    @FetchRequest private var triggers: FetchedResults<DBCacheTrigger>

    init(name: String, owner: String) {
        _triggers = FetchRequest<DBCacheTrigger>(
            sortDescriptors: [],
            predicate: NSPredicate(format: "name_ = %@ and owner_ = %@", name, owner)
        )
    }

    var body: some View {
        if let trigger = triggers.first {
            Section("Trigger") {
                LabeledContent("Type", value: trigger.type)
                LabeledContent("Action Type", value: trigger.actionType)
                LabeledContent("Event", value: trigger.event)
                LabeledContent("When", value: trigger.whenClause ?? Constants.nullValue)
            }
            Section("Base Object") {
                LabeledContent("Type", value: trigger.objectType)
                LabeledContent("Owner", value: trigger.objectOwner ?? Constants.nullValue)
                LabeledContent("Name", value: trigger.objectName ?? Constants.nullValue)
            }
            Section("Firing") {
                LabeledContent("Enabled") {
                    BoolIndicator(value: trigger.isEnabled, trueColor: .green, falseColor: .red)
                }
            }
        }
    }
}
