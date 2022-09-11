//
//  QuickFilterView.swift
//  Macintora
//
//  Created by Ilia Sazonov on 8/31/22.
//

import SwiftUI

struct GridControlGroupStyle: ControlGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
//        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: .infinity), spacing: 0, alignment: .leading)], alignment: .leading, spacing: 2) {
        LazyVGrid(columns: [GridItem(.fixed(120)), GridItem(.fixed(110))], alignment: .leading, spacing: 5) {
            configuration.content
                .toggleStyle(.switch)
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
                    Toggle(isOn: $quickFilters.showTables) { Text( "Tables").frame(width: 70, alignment: .leading) }
                    Toggle(isOn: $quickFilters.showViews) { Text("Views").frame(width: 70, alignment: .leading)}
                    Toggle(isOn: $quickFilters.showIndexes) { Text("Indexes").frame(width: 70, alignment: .leading)}
                    Toggle(isOn: $quickFilters.showPackages) { Text("Packages").frame(width: 70, alignment: .leading)}
                    Toggle(isOn: $quickFilters.showTypes) { Text("Types").frame(width: 70, alignment: .leading)}
                    Toggle(isOn: $quickFilters.showTriggers) { Text("Triggers").frame(width: 70, alignment: .leading)}
                    Toggle(isOn: $quickFilters.showProcedures) { Text("Procedures").frame(width: 70, alignment: .leading)}
                        .disabled(true)
                    Toggle(isOn: $quickFilters.showFunctions) { Text("Functions").frame(width: 70, alignment: .leading)}
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
