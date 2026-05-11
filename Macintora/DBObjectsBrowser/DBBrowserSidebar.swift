//
//  DBBrowserSidebar.swift
//  Macintora
//
//  Sidebar composition: 52px-wide type rail on the left + native sectioned
//  List of objects on the right. The rail filters the list to a single
//  Oracle object type by mutating `selectedTypeFilter` on the criteria.
//
//  A "Pinned" section is rendered above the type-scoped owner sections.
//  Pinned objects come from `DBBrowserPinnedStore` (per-TNS, UserDefaults).
//

import SwiftUI
import CoreData

struct DBBrowserSidebar: View {
    let items: SectionedFetchResults<String?, DBCacheObject>
    @ObservedObject var cache: DBCacheVM
    @ObservedObject var pinned: DBBrowserPinnedStore
    @Binding var listSelection: SectionedFetchResults<String?, DBCacheObject>.Section.Element?
    let onContextAction: (DBCacheRowAction, DBCacheObject) -> Void

    var body: some View {
        HStack(spacing: 0) {
            DBBrowserTypeRail(criteria: $cache.searchCriteria)
                .frame(width: 52)

            Divider()

            DBBrowserObjectList(
                items: items,
                pinned: pinned,
                listSelection: $listSelection,
                onContextAction: onContextAction
            )
        }
    }
}

// MARK: - Type rail

/// Vertical column of object types. Tapping a type pins the list to that one
/// type via `selectedTypeFilter`; tapping the already-active type clears the
/// pin and falls back to the per-type toggles.
struct DBBrowserTypeRail: View {
    @Binding var criteria: DBCacheSearchCriteria

    var body: some View {
        VStack(spacing: 2) {
            ForEach(OracleObjectType.displayOrder, id: \.self) { type in
                TypeRailButton(
                    type: type,
                    isSelected: criteria.selectedTypeFilter == type.rawValue
                ) {
                    toggle(type)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
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

private struct TypeRailButton: View {
    let type: OracleObjectType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: type.symbolName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(type.tint)
                    .frame(width: 24, height: 20)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background {
                if isSelected {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.18))
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: 2)
                        }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(type.label + "s — \(isSelected ? "click to clear filter" : "click to scope to this type")")
        .accessibilityLabel("Filter by \(type.label)s")
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
                            row(for: item, showPin: true)
                        }
                    } header: {
                        Label("Pinned", systemImage: "pin.fill")
                            .foregroundStyle(.tint)
                    }
                    .headerProminence(.increased)
                }

                ForEach(items) { section in
                    Section {
                        ForEach(section) { item in
                            row(for: item)
                        }
                    } header: {
                        Text(section.id ?? "(unknown)")
                    }
                    .headerProminence(.increased)
                }
            }
            .listStyle(.sidebar)
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
        // Preserve user-defined pin order (insertion order in the store).
        let positions = Dictionary(uniqueKeysWithValues: pinned.keys.enumerated().map { ($1, $0) })
        return found.sorted { positions[DBPinnedKey($0), default: .max] < positions[DBPinnedKey($1), default: .max] }
    }

    @ViewBuilder
    private func row(for item: DBCacheObject, showPin: Bool = false) -> some View {
        let pinKey = DBPinnedKey(item)
        DBCacheListEntryView(dbObject: item, showPinIndicator: !showPin && pinned.isPinned(pinKey))
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
