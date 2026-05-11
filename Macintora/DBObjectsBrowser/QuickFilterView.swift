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
            Section("Object Types") {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 100), alignment: .leading),
                        GridItem(.flexible(minimum: 100), alignment: .leading)
                    ],
                    alignment: .leading,
                    spacing: 6
                ) {
                    Toggle("Tables", isOn: typeToggle(\.showTables))
                    Toggle("Views", isOn: typeToggle(\.showViews))
                    Toggle("Indexes", isOn: typeToggle(\.showIndexes))
                    Toggle("Packages", isOn: typeToggle(\.showPackages))
                    Toggle("Types", isOn: typeToggle(\.showTypes))
                    Toggle("Triggers", isOn: typeToggle(\.showTriggers))
                    Toggle("Procedures", isOn: typeToggle(\.showProcedures))
                    Toggle("Functions", isOn: typeToggle(\.showFunctions))
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

struct QuickFilterView_Previews: PreviewProvider {
    static var previews: some View {
        QuickFilterView(quickFilters: .constant(DBCacheSearchCriteria(for: "preview")))
    }
}
