//
//  TableTableColumnsView.swift
//  Macintora
//

import CoreData
import SwiftUI

struct TableTableColumnsView: View {
    @Environment(\.managedObjectContext) var context
    @FetchRequest private var columns: FetchedResults<DBCacheTableColumn>
    @Binding var childSelection: DBChildSelection?
    @State private var selectedRow: DBCacheTableColumn.ID?
    // Default to the fetch-order sort (internal column id). Per Apple docs the
    // Table itself needs a `sortOrder` binding for header-click sorts to flow;
    // without it, `value:` columns *look* sortable but clicks do nothing.
    @State private var sortOrder: [KeyPathComparator<DBCacheTableColumn>] = [
        KeyPathComparator(\DBCacheTableColumn.internalColumnID)
    ]

    init(dbObject: DBCacheObject, childSelection: Binding<DBChildSelection?>) {
        _columns = FetchRequest<DBCacheTableColumn>(
            sortDescriptors: [NSSortDescriptor(keyPath: \DBCacheTableColumn.internalColumnID, ascending: true)],
            predicate: NSPredicate(format: "tableName_ = %@ and owner_ = %@", dbObject.name, dbObject.owner)
        )
        _childSelection = childSelection
    }

    var body: some View {
        // String columns combine `value:` (sort key) with a content closure
        // via the `(_, value:, comparator:, content:)` initializer (default
        // `.localizedStandard` comparator). Non-String columns use the
        // `(_, sortUsing:, content:)` form with an explicit
        // `KeyPathComparator`. Both forms erase to
        // `KeyPathComparator<DBCacheTableColumn>` so they share a single
        // `sortOrder` array.
        let sorted = columns.sorted(using: sortOrder)
        Table(sorted, selection: $selectedRow, sortOrder: $sortOrder) {
            TableColumn("Column ID", sortUsing: KeyPathComparator(\DBCacheTableColumn.columnIDSortKey)) { value in
                cellText((value.columnID as? Int)?.formatted() ?? "", hidden: value.isHidden)
            }
            TableColumn("Column Name", value: \.columnName) { value in
                cellText(value.columnName, hidden: value.isHidden)
            }
            TableColumn("Datatype", value: \.dataType) { value in
                cellText(value.dataType, hidden: value.isHidden)
            }
            TableColumn("Length", sortUsing: KeyPathComparator(\DBCacheTableColumn.length)) { value in
                cellText(value.length.formatted(), hidden: value.isHidden)
            }
            TableColumn("Nullable", sortUsing: KeyPathComparator(\DBCacheTableColumn.isNullableSortKey)) { value in
                BoolIndicator(value: value.isNullable)
                    .opacity(value.isHidden ? 0.6 : 1)
            }
            TableColumn("Identity", sortUsing: KeyPathComparator(\DBCacheTableColumn.isIdentitySortKey)) { value in
                BoolIndicator(value: value.isIdentity)
                    .opacity(value.isHidden ? 0.6 : 1)
            }
            TableColumn("Default", sortUsing: KeyPathComparator(\DBCacheTableColumn.defaultValueSortKey)) { value in
                cellText(value.defaultValue ?? "", hidden: value.isHidden)
            }
        }
        .font(.system(.body, design: .monospaced))
        .onChange(of: selectedRow) { _, newID in
            childSelection = newID
                .flatMap { id in columns.first { $0.id == id } }
                .map(DBChildSelection.column)
        }
    }

    @ViewBuilder
    private func cellText(_ s: String, hidden: Bool) -> some View {
        if hidden {
            Text(s).italic().foregroundStyle(.secondary)
        } else {
            Text(s)
        }
    }
}

// Sort-key shims for properties that aren't directly Comparable.
// `KeyPathComparator` requires `Value: Comparable & Sendable`; NSNumber? and
// Optional<String> don't qualify. Columns without a value (hidden/system
// columns whose `columnID` is null) sort after the rest by collapsing nil
// to `Int.max` / `""`.
extension DBCacheTableColumn {
    @objc var columnIDSortKey: Int { (columnID as? Int) ?? .max }
    @objc var defaultValueSortKey: String { defaultValue ?? "" }
    // Bool isn't Comparable, so `KeyPathComparator(\.isFoo)` won't compile;
    // promote to Int (0 = false, 1 = true) so unticked rows sort first.
    @objc var isNullableSortKey: Int { isNullable ? 1 : 0 }
    @objc var isIdentitySortKey: Int { isIdentity ? 1 : 0 }
}
