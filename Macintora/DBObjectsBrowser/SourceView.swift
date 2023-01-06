//
//  SourceView.swift
//  Macintora
//
//  Created by Ilia Sazonov on 9/7/22.
//

import SwiftUI
import CodeEditor

struct SourceView: View {
    @Binding var objName: String
    @Binding var text: String
    @State var title: String
    
    init(objName: Binding<String>, text: Binding<String>, title: String) {
        self._objName = objName
        self._text = text
        self.title = title
    }
    
    var body: some View {
        VStack {
            HStack {
                Text(title)
                    .font(.title2)
                    .frame(alignment:.leading)
                
                Spacer()
                
                Button {
                    let formatter = Formatter()
                    formatter.formattedSource = "...formatting, please wait..."
                    
                    SwiftUIWindow.open {window in
                        let _ = (window.title = objName)
                        FormattedView(formatter: formatter)
                    }
                    .closeOnEscape(true)
                    
                    formatter.formatSource(name: objName, text: text)
                }
                label: { Text("Format&View") }
                
                Button {
                    let formatter = Formatter()
                    formatter.formattedSource = "...formatting, please wait..."
                    Task.detached(priority: .background) { [self, text] in
                        formatter.formatSource(name: objName, text: text)
                    }
                }
                label: { Text("Format&Save") }
                    .disabled(true)
            }
            Text("\(text)")
                .monospaced()
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
//            CodeEditor(source: $text, language: .pgsql, theme: .atelierDuneLight, flags: [.selectable, .editable], autoscroll: false, wordWrap: .constant(true))
                .frame(maxWidth: .infinity, minHeight: 100, idealHeight: 300, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

//struct SourceView_Preview: PreviewProvider {
//    static var previews: some View {
//        SourceView(objName: .constant("ObjectName"), text: .constant("this is the source code sample"), title: "Title")
//            .frame(width: 800, height: 800)
//    }
//}
