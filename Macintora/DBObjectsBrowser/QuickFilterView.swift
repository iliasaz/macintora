//
//  QuickFilterView.swift
//  Macintora
//
//  Created by Ilia Sazonov on 8/31/22.
//

import SwiftUI

struct QuickFilterView: View {
    @Binding var quickFilters: DBCacheSearchCriteria

    /// Sub-binding for a per-type toggle that also clears the transient
    /// "ignore type filter" override the moment the user adjusts a toggle —
    /// touching one means they want the toggles to take effect again.
    private func typeToggle(_ keyPath: WritableKeyPath<DBCacheSearchCriteria, Bool>) -> Binding<Bool> {
        Binding(
            get: { quickFilters[keyPath: keyPath] },
            set: { newValue in
                quickFilters[keyPath: keyPath] = newValue
                quickFilters.ignoreTypeFilter = false
            }
        )
    }

    var body: some View {
        Form {
            Section("Presets") {
                FilterPresetRow(criteria: $quickFilters)
            }

            Section("Object Types") {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 100), alignment: .leading),
                        GridItem(.flexible(minimum: 100), alignment: .leading)
                    ],
                    alignment: .leading,
                    spacing: 6
                ) {
                    TypeToggle(type: .table,     isOn: typeToggle(\.showTables))
                    TypeToggle(type: .view,      isOn: typeToggle(\.showViews))
                    TypeToggle(type: .index,     isOn: typeToggle(\.showIndexes))
                    TypeToggle(type: .package,   isOn: typeToggle(\.showPackages))
                    TypeToggle(type: .type,      isOn: typeToggle(\.showTypes))
                    TypeToggle(type: .trigger,   isOn: typeToggle(\.showTriggers))
                    TypeToggle(type: .procedure, isOn: typeToggle(\.showProcedures))
                    TypeToggle(type: .function,  isOn: typeToggle(\.showFunctions))
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                if quickFilters.selectedTypeFilter != nil {
                    Button("Show all types") {
                        quickFilters.selectedTypeFilter = nil
                    }
                    .controlSize(.small)
                }
            }

            Section("Schemas") {
                TextField("ex. SYSTEM, SYS", text: $quickFilters.ownerString)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
            }

            Section("Object Prefix") {
                TextField("ex. DBMS, DBA", text: $quickFilters.prefixString)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
            }
        }
        .formStyle(.grouped)
    }
}

/// Toggle row that pairs the on/off switch with the type's identity colored icon.
private struct TypeToggle: View {
    let type: OracleObjectType
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label {
                Text(type.label + "s")
            } icon: {
                Image(systemName: type.symbolName)
                    .foregroundStyle(type.tint)
            }
        }
    }
}

/// Horizontal pill row of preset chips. The chip whose state matches the
/// current criteria is highlighted; if no preset matches, "Custom" lights up.
private struct FilterPresetRow: View {
    @Binding var criteria: DBCacheSearchCriteria

    var body: some View {
        let current = criteria.matchingPreset
        HStack(spacing: 6) {
            ForEach(DBCacheFilterPreset.allCases) { preset in
                PresetChip(label: preset.label, isOn: current == preset) {
                    criteria.applyPreset(preset)
                }
            }
            PresetChip(label: "Custom", isOn: current == nil, action: nil)
            Spacer(minLength: 0)
        }
        .controlSize(.small)
    }
}

private struct PresetChip: View {
    let label: String
    let isOn: Bool
    let action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) {
                chipBody
            }
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
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .foregroundStyle(isOn ? .white : .secondary)
            .background {
                Capsule().fill(isOn ? Color.accentColor : Color.secondary.opacity(0.12))
            }
            .contentShape(.capsule)
    }
}

struct QuickFilterView_Previews: PreviewProvider {
    static var previews: some View {
        QuickFilterView(quickFilters: .constant(DBCacheSearchCriteria(for: "preview")))
    }
}
