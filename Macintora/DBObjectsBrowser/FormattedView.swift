//
//  FormattedView.swift
//  DBObjectsBrowser
//
//  Created by Ilia on 6/8/22.
//

import SwiftUI

struct FormattedView: View {
    @ObservedObject var formatter: Formatter
    @State private var selection: Range<String.Index> = "".startIndex..<"".endIndex

    var body: some View {
        MacintoraEditor(
            text: $formatter.formattedSource,
            selection: $selection,
            language: .sql,
            isEditable: false,
            isSelectable: true,
            wordWrap: .constant(true),
            showsLineNumbers: false,
            highlightsSelectedLine: false,
            accessibilityIdentifier: "editor.db.formatted"
        )
        .frame(minWidth: 400, idealWidth: 1000, maxWidth: .infinity, minHeight: 400, idealHeight: 1000, maxHeight: .infinity)
    }
}

//struct FormattedView_Previews: PreviewProvider {
//    static var previews: some View {
//        FormattedView()
//    }
//}
