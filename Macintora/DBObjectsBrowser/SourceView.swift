//
//  SourceView.swift
//  Macintora
//
//  Created by Ilia Sazonov on 9/7/22.
//

import SwiftUI

struct SourceView: View {
    @Binding var objName: String
    @Binding var text: String
    @State var title: String
    @State private var selection: Range<String.Index> = "".startIndex..<"".endIndex

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

                    Task { [objName, text] in
                        let formatted = await formatter.formatSource(name: objName, text: text)
                        formatter.formattedSource = formatted
                    }
                }
                label: { Text("Format&View") }
                
                Button {
                    let formatter = Formatter()
                    formatter.formattedSource = "...formatting, please wait..."
                    Task { [self, text] in
                        _ = await formatter.formatSource(name: objName, text: text)
                    }
                }
                label: { Text("Format&Save") }
                    .disabled(true)
            }
//            ScrollView {
//                Text("\(text)")
//                    .monospaced()
//                    .textSelection(.enabled)
//                    .lineLimit(nil)
//                    .multilineTextAlignment(.leading)
//                    .frame(maxWidth: .infinity)
//            }
            MacintoraEditor(
                text: $text,
                selection: $selection,
                language: .plsql,
                isEditable: true,
                isSelectable: true,
                wordWrap: .constant(true),
                showsLineNumbers: true,
                highlightsSelectedLine: false,
                accessibilityIdentifier: "editor.db.source"
            )
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
