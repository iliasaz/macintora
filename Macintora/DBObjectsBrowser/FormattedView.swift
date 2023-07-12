//
//  FormattedView.swift
//  DBObjectsBrowser
//
//  Created by Ilia on 6/8/22.
//

import SwiftUI
import CodeEditor
import CodeEditTextView


struct FormattedView: View {
    @ObservedObject var formatter: Formatter
    @State var cursorPosition = (0,0)
    
    var body: some View {
//        CodeEditor(source: $formatter.formattedSource, language: .pgsql, theme: .atelierDuneLight, flags: [.selectable], autoscroll: false, wordWrap: .constant(true))

        CodeEditTextView($formatter.formattedSource, language: .sql, theme: sqlTheme, font: sourceFont, tabWidth: tabWidth, lineHeight: lineHeight, wrapLines: true, editorOverscroll: editorOverscroll, cursorPosition: $cursorPosition, isEditable: true)
            .frame(minWidth: 400, idealWidth: 1000, maxWidth: .infinity, minHeight: 400, idealHeight: 1000, maxHeight: .infinity)
    }
}

//struct FormattedView_Previews: PreviewProvider {
//    static var previews: some View {
//        FormattedView()
//    }
//}
