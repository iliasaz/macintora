//
//  QuickFilterView.swift
//  Macintora
//
//  Created by Ilia Sazonov on 8/31/22.
//
//  The "Filter & scope" popover (v2 design A + presets). Shown from the
//  toolbar's Filter button. All edits are live — the object list refreshes
//  as you change toggles — so "Apply" just dismisses.
//

import SwiftUI
import CoreData

struct QuickFilterView: View {
    @Binding var quickFilters: DBCacheSearchCriteria
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var distinctOwners: [String] = []
    @State private var matchCount: Int = 0
    @State private var totalCount: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    presetsSection
                    Divider()
                    typesSection
                    Divider()
                    schemasSection
                    Divider()
                    nameSection
                }
            }
            .frame(maxHeight: 460)

            Divider()
            footer
        }
        .frame(width: 360)
        .task { await loadOwners() }
        .task(id: quickFilters) { await refreshCounts() }
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)
            Text("Filter & scope").font(.headline)
            Spacer()
            Button("Reset") { quickFilters.reset() }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .font(.subheadline)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Matches \(matchCount.formatted()) of \(totalCount.formatted()) objects")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Apply") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Sections

    private var presetsSection: some View {
        Section {
            FilterPresetRow(criteria: $quickFilters)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        } header: {
            SectionCaption("Presets")
        }
    }

    private var typesSection: some View {
        Section {
            LazyVGrid(
                columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(OracleObjectType.displayOrder, id: \.self) { type in
                    if let keyPath = DBCacheSearchCriteria.showKeyPath(for: type) {
                        TypeCheckRow(type: type, isOn: typeToggle(keyPath))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            if quickFilters.selectedTypeFilter != nil {
                Button("Show all types") { quickFilters.selectedTypeFilter = nil }
                    .controlSize(.small)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        } header: {
            SectionCaption("Object types")
        }
    }

    private var schemasSection: some View {
        Section {
            if distinctOwners.isEmpty {
                Text("No schemas cached yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(distinctOwners, id: \.self) { owner in
                        SchemaPill(
                            owner: owner,
                            isOn: ownerIsIncluded(owner),
                            action: { toggleOwner(owner) }
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        } header: {
            SectionCaption("Schemas")
        }
    }

    private var nameSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Starts with").font(.caption2).foregroundStyle(.tertiary)
                    TextField("DBMS, DBA", text: $quickFilters.prefixString)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .disableAutocorrection(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Excluding").font(.caption2).foregroundStyle(.tertiary)
                    TextField("AQ$_, MLOG$_, BIN$", text: $quickFilters.excludePrefixString)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .disableAutocorrection(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        } header: {
            SectionCaption("Name")
        }
    }

    // MARK: - Bindings & helpers

    private func typeToggle(_ keyPath: WritableKeyPath<DBCacheSearchCriteria, Bool>) -> Binding<Bool> {
        Binding(
            get: { quickFilters[keyPath: keyPath] },
            set: { newValue in
                quickFilters[keyPath: keyPath] = newValue
                quickFilters.ignoreTypeFilter = false
            }
        )
    }

    /// A pill is "on" when its owner is in the inclusion list, or when the
    /// inclusion list is empty (empty == every schema included).
    private func ownerIsIncluded(_ owner: String) -> Bool {
        let list = quickFilters.ownerInclusionList
        return list.isEmpty || list.contains(owner.uppercased())
    }

    private func toggleOwner(_ owner: String) {
        let upper = owner.uppercased()
        var list = quickFilters.ownerInclusionList
        if list.isEmpty {
            // Switching out of "all" mode: start an explicit list with just
            // the *other* schemas would be surprising; start with this one.
            list = [upper]
        } else if let idx = list.firstIndex(of: upper) {
            list.remove(at: idx)
        } else {
            list.append(upper)
        }
        quickFilters.ownerString = list.joined(separator: ", ")
    }

    // MARK: - Async loads

    private func loadOwners() async {
        let req = NSFetchRequest<NSDictionary>(entityName: "DBCacheObject")
        req.resultType = .dictionaryResultType
        req.propertiesToFetch = ["owner_"]
        req.returnsDistinctResults = true
        req.sortDescriptors = [NSSortDescriptor(key: "owner_", ascending: true)]
        let rows = (try? viewContext.fetch(req)) ?? []
        distinctOwners = rows.compactMap { $0["owner_"] as? String }
    }

    private func refreshCounts() async {
        let total = DBCacheObject.fetchRequest()
        totalCount = (try? viewContext.count(for: total)) ?? 0
        let matching = DBCacheObject.fetchRequest()
        matching.predicate = quickFilters.predicate
        matchCount = (try? viewContext.count(for: matching)) ?? 0
    }
}

// MARK: - Small pieces

private struct SectionCaption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.5)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }
}

/// Checkbox + colored type icon + label + monospaced count.
private struct TypeCheckRow: View {
    let type: OracleObjectType
    @Binding var isOn: Bool
    @Environment(\.managedObjectContext) private var viewContext
    @State private var count: Int = 0

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 6) {
                Image(systemName: type.symbolName)
                    .foregroundStyle(type.tint)
                    .frame(width: 16)
                Text(type.label + "s")
                Spacer(minLength: 4)
                Text(count, format: .number)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .toggleStyle(.checkbox)
        .task {
            let req = DBCacheObject.fetchRequest()
            req.predicate = NSPredicate(format: "type_ = %@", type.rawValue)
            count = (try? viewContext.count(for: req)) ?? 0
        }
    }
}

private struct SchemaPill: View {
    let owner: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(owner)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity)
                .foregroundStyle(isOn ? .white : .secondary)
                .background(Capsule().fill(isOn ? Color.accentColor : Color.secondary.opacity(0.12)))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(isOn ? "Click to exclude \(owner)" : "Click to include \(owner)")
    }
}

/// Horizontal pill row of presets. The chip matching the current state is
/// highlighted; "Custom" lights up when none match.
private struct FilterPresetRow: View {
    @Binding var criteria: DBCacheSearchCriteria

    var body: some View {
        let current = criteria.matchingPreset
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(DBCacheFilterPreset.allCases) { preset in
                PresetChip(label: preset.label, isOn: current == preset) {
                    criteria.applyPreset(preset)
                }
            }
            PresetChip(label: "Custom", isOn: current == nil, action: nil)
        }
    }
}

private struct PresetChip: View {
    let label: String
    let isOn: Bool
    let action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { chipBody }
                .buttonStyle(.plain)
        } else {
            chipBody
        }
    }

    @ViewBuilder
    private var chipBody: some View {
        Text(label)
            .font(.caption)
            .fontWeight(.medium)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity)
            .foregroundStyle(isOn ? .white : .secondary)
            .background(Capsule().fill(isOn ? Color.accentColor : Color.secondary.opacity(0.12)))
            .contentShape(.capsule)
    }
}

struct QuickFilterView_Previews: PreviewProvider {
    static var previews: some View {
        QuickFilterView(quickFilters: .constant(DBCacheSearchCriteria(for: "preview")))
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
