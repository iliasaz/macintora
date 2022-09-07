//
//  FormattedView.swift
//  DBObjectsBrowser
//
//  Created by Ilia on 6/8/22.
//

import SwiftUI
import CodeEditor

struct FormattedView: View {
    @Binding var formattedSource: String
    
    var body: some View {
        CodeEditor(source: $formattedSource, language: .pgsql, theme: .atelierDuneLight, flags: [.selectable], autoscroll: false)
            .frame(minWidth: 400, idealWidth: 1000, maxWidth: .infinity, minHeight: 400, idealHeight: 1000, maxHeight: .infinity)
    }
}

//struct FormattedView_Previews: PreviewProvider {
//    static var previews: some View {
//        FormattedView()
//    }
//}
