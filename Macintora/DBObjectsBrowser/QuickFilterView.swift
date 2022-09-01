//
//  QuickFilterView.swift
//  Macintora
//
//  Created by Ilia Sazonov on 8/31/22.
//

import SwiftUI

struct GridControlGroupStyle: ControlGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80, maximum: .infinity), spacing: 5, alignment: .leading)], alignment: .leading, spacing: 5) {
            configuration.content
                .toggleStyle(.checkbox)
                .padding(0)
        }
    }
}

struct QuickFilterView: View {
    @Binding var quickFilters: DBCacheSearchCriteria
    @State private var isQuickFilterViewExpanded = true

    var body: some View {
        DisclosureGroup("Quick Filters", isExpanded: $isQuickFilterViewExpanded) {
            VStack {
                ControlGroup {
                    Toggle("Tables", isOn: $quickFilters.showTables)
                    Toggle("Views", isOn: $quickFilters.showViews)
                    Toggle("Indexes", isOn: $quickFilters.showIndexes)
                    Toggle("Packages", isOn: $quickFilters.showPackages)
                    Toggle("Types", isOn: $quickFilters.showTypes)
                    Toggle("Procedures", isOn: $quickFilters.showProcedures)
                        .disabled(true)
                    Toggle("Functions", isOn: $quickFilters.showFunctions)
                        .disabled(true)
                }
                .controlGroupStyle(GridControlGroupStyle())
                .padding(.horizontal)
                
                TextField("Schemas, ex. SYSTEM,SYS", text: $quickFilters.ownerString)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    .padding(.horizontal)
                
                TextField("Object Prefix, ex. DBMS,DBA", text: $quickFilters.prefixString)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .padding(.horizontal)
    }
}

struct QuickFilterView_Previews: PreviewProvider {
    static var previews: some View {
        QuickFilterView(quickFilters: .constant(DBCacheSearchCriteria(for: "preview")))
    }
}
