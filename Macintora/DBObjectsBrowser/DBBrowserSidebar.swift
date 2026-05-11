//
//  DBBrowserSidebar.swift
//  Macintora
//
//  Sidebar composition: a vertical type rail on the left + the native
//  sectioned object List on the right. The rail filters the list to a single
//  Oracle object type via `selectedTypeFilter`; a "Pinned" section sits above
//  the per-owner sections.
//
//  Both panes are built from `List` so they inherit the macOS source-list
//  treatment — most importantly, the rows are inset below the unified title
//  bar instead of being painted under the traffic lights.
//

import SwiftUI
import CoreData

struct DBBrowserSidebar: View {
    let items: SectionedFetchResults<String?, DBCacheObject>
    @ObservedObject var cache: DBCacheVM
    @ObservedObject var pinned: DBBrowserPinnedStore
    @Binding var listSelection: SectionedFetchResults<String?, DBCacheObject>.Section.Element?
    let onContextAction: (DBCacheRowAction, DBCacheObject) -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @State private var typeCounts: [String: Int] = [:]
    @State private var typesWithInvalid: Set<String> = []

    var body: some View {
        HStack(spacing: 0) {
            DBBrowserTypeRail(
                criteria: $cache.searchCriteria,
                counts: typeCounts,
                typesWithInvalid: typesWithInvalid
            )
            .frame(width: 56)

            Divider()

            DBBrowserObjectList(
                items: items,
                pinned: pinned,
                listSelection: $listSelection,
                onContextAction: onContextAction
            )
        }
        .task(id: cache.lastUpdatedStr) {
            await refreshTypeStats()
        }
    }

    /// Total per-type object counts (ignoring the live filter — the rail must
    /// show what's *available* so the user can switch to it) plus which types
    /// currently have at least one invalid object.
    private func refreshTypeStats() async {
        let context = viewContext
        var counts: [String: Int] = [:]
        var invalid: Set<String> = []
        for type in OracleObjectType.displayOrder {
            let raw = type.rawValue
            let countReq = DBCacheObject.fetchRequest()
            countReq.predicate = NSPredicate(format: "type_ = %@", raw)
            counts[raw] = (try? context.count(for: countReq)) ?? 0
            let invalidReq = DBCacheObject.fetchRequest()
            invalidReq.predicate = NSPredicate(format: "type_ = %@ AND isValid == NO", raw)
            if let invalidCount = try? context.count(for: invalidReq), invalidCount > 0 {
                invalid.insert(raw)
            }
        }
        typeCounts = counts
        typesWithInvalid = invalid
    }
}

// MARK: - Type rail

/// Vertical column of object types. Tapping a type pins the list to that one
/// type via `selectedTypeFilter`; tapping the already-active type clears it.
struct DBBrowserTypeRail: View {
    @Binding var criteria: DBCacheSearchCriteria
    let counts: [String: Int]
    let typesWithInvalid: Set<String>

    var body: some View {
        List {
            ForEach(OracleObjectType.displayOrder, id: \.self) { type in
                TypeRailRow(
                    type: type,
                    count: counts[type.rawValue] ?? 0,
                    hasInvalid: typesWithInvalid.contains(type.rawValue),
                    isSelected: criteria.selectedTypeFilter == type.rawValue
                ) {
                    toggle(type)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.sidebar)
        .scrollIndicators(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
    }

    private func toggle(_ type: OracleObjectType) {
        if criteria.selectedTypeFilter == type.rawValue {
            criteria.selectedTypeFilter = nil
        } else {
            criteria.selectedTypeFilter = type.rawValue
            criteria.ignoreTypeFilter = false
        }
    }
}

private struct TypeRailRow: View {
    let type: OracleObjectType
    let count: Int
    let hasInvalid: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: type.symbolName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : type.tint)
                    .frame(height: 18)
                    .overlay(alignment: .topTrailing) {
                        if hasInvalid {
                            Circle()
                                .fill(.red)
                                .frame(width: 5, height: 5)
                                .offset(x: 6, y: -2)
                        }
                    }
                Text(count, format: .number)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(alignment: .leading) {
                if isSelected {
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.accentColor.opacity(0.16))
                        Rectangle().fill(Color.accentColor).frame(width: 2)
                    }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("\(type.label)s — \(isSelected ? "click to clear filter" : "click to show only \(type.label.lowercased())s")")
        .accessibilityLabel("\(type.label)s, \(count)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Object list

struct DBBrowserObjectList: View {
    let items: SectionedFetchResults<String?, DBCacheObject>
    @ObservedObject var pinned: DBBrowserPinnedStore
    @Binding var listSelection: SectionedFetchResults<String?, DBCacheObject>.Section.Element?
    let onContextAction: (DBCacheRowAction, DBCacheObject) -> Void

    var body: some View {
        if items.isEmpty && pinnedRows.isEmpty {
            ContentUnavailableView.search
        } else {
            List(selection: $listSelection) {
                if !pinnedRows.isEmpty {
                    Section {
                        ForEach(pinnedRows) { item in
                            row(for: item, inPinnedSection: true)
                        }
                    } header: {
                        sectionHeader(
                            title: Text("Pinned"),
                            count: pinnedRows.count,
                            systemImage: "pin.fill",
                            tint: true
                        )
                    }
                    .headerProminence(.increased)
                }

                ForEach(items) { section in
                    Section {
                        ForEach(section) { item in
                            row(for: item)
                        }
                    } header: {
                        sectionHeader(title: Text(section.id ?? "(unknown)"), count: section.count)
                    }
                    .headerProminence(.increased)
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private func sectionHeader(title: Text, count: Int, systemImage: String? = nil, tint: Bool = false) -> some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(tint ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            title
            Spacer(minLength: 4)
            Text(count, format: .number)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
    }

    /// Pinned objects that are actually present in the current fetch result.
    /// We don't show stale pins (the underlying row was dropped) because
    /// selecting one wouldn't reveal anything.
    private var pinnedRows: [DBCacheObject] {
        let needed = Set(pinned.keys)
        guard !needed.isEmpty else { return [] }
        var found: [DBCacheObject] = []
        for section in items {
            for obj in section where needed.contains(DBPinnedKey(obj)) {
                found.append(obj)
            }
        }
        let positions = Dictionary(uniqueKeysWithValues: pinned.keys.enumerated().map { ($1, $0) })
        return found.sorted { positions[DBPinnedKey($0), default: .max] < positions[DBPinnedKey($1), default: .max] }
    }

    @ViewBuilder
    private func row(for item: DBCacheObject, inPinnedSection: Bool = false) -> some View {
        let pinKey = DBPinnedKey(item)
        DBCacheListEntryView(
            dbObject: item,
            showPinIndicator: !inPinnedSection && pinned.isPinned(pinKey)
        )
        .tag(item)
        .draggable("\(item.owner).\(item.name)") {
            DBCacheListEntryView(dbObject: item)
        }
        .contextMenu {
            Button("Copy Name") { onContextAction(.copyName, item) }
            Button("Copy Owner.Name") { onContextAction(.copyQualifiedName, item) }
            Divider()
            Button(pinned.isPinned(pinKey) ? "Unpin" : "Pin") {
                pinned.toggle(pinKey)
            }
            Divider()
            Button("Reveal in Sidebar") { onContextAction(.reveal, item) }
            Button("Open in New Window") { onContextAction(.openInNewWindow, item) }
            Button("Open Source in Editor") { onContextAction(.editSource, item) }
        }
    }
}
