//
//  SourceView.swift
//  Macintora
//
//  Created by Ilia Sazonov on 9/7/22.
//

import SwiftUI
import CodeEditor

struct SourceView: View {
    @State var objName: String
    @State var text: String?
    @State var title: String
    
    var body: some View {
        VStack {
            HStack {
                Text(title)
                    .font(.title2)
                    .frame(alignment:.leading)
                Spacer()
                Button {
                    let formatter = Formatter()
                    var formattedSource = "...formatting, please wait..."
                    Task.init(priority: .background) { formattedSource = await formatter.formatSource(name: objName, text: text) }
                    SwiftUIWindow.open {window in
                        let _ = (window.title = objName)
                        FormattedView(formattedSource: Binding(get: { formattedSource }, set: {_ in }) )
                    }
                    .closeOnEscape(true)
                }
            label: { Text("Format Source") }
            }
            CodeEditor(source: .constant(text ?? "N/A"), language: .pgsql, theme: .atelierDuneLight, flags: [.selectable], autoscroll: false)
                .frame(maxWidth: .infinity, minHeight: 100, idealHeight: 300, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
