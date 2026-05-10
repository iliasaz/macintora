//
//  QuickFilterView.swift
//  Macintora
//
//  Created by Ilia Sazonov on 8/31/22.
//

import SwiftUI

struct QuickFilterView: View {
    @Binding var quickFilters: DBCacheSearchCriteria

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
                    Toggle("Tables", isOn: $quickFilters.showTables)
                    Toggle("Views", isOn: $quickFilters.showViews)
                    Toggle("Indexes", isOn: $quickFilters.showIndexes)
                    Toggle("Packages", isOn: $quickFilters.showPackages)
                    Toggle("Types", isOn: $quickFilters.showTypes)
                    Toggle("Triggers", isOn: $quickFilters.showTriggers)
                    Toggle("Procedures", isOn: $quickFilters.showProcedures)
                    Toggle("Functions", isOn: $quickFilters.showFunctions)
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
