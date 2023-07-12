//
//  SourceView.swift
//  Macintora
//
//  Created by Ilia Sazonov on 9/7/22.
//

import SwiftUI
import CodeEditor
import CodeEditTextView


let sqlTheme = EditorTheme.init(
    text: .textColor.withAlphaComponent(0.7),
    insertionPoint: .controlAccentColor ,
    invisibles: .lightGray,
    background: .textBackgroundColor,
    lineHighlight: .unemphasizedSelectedContentBackgroundColor ,
    selection: .selectedTextBackgroundColor,
    keywords: keywordColor,
    commands: .yellow,
    types: .orange,
    attributes: .brown,
    variables: .textColor.withAlphaComponent(0.7),
    values: .magenta,
    numbers: numberColor,
    strings: stringColor,
    characters: .green,
    comments: .lightGray)

let sourceFont = NSFont(name: "SF Mono", size: 12.0)!
let keywordColor = NSColor.fromHexString(hex: "#b854d4", alpha: 0.5)!
let numberColor = NSColor.fromHexString(hex: "#b65611", alpha: 1.0)!
let stringColor = NSColor.fromHexString(hex: "#60AC39", alpha: 1.0)!
let tabWidth = 4
let lineHeight = 1.2
let editorOverscroll = 0.3

struct SourceView: View {
    @Binding var objName: String
    @Binding var text: String
    @State var title: String
    @State var cursorPosition = (0,0)
    
    init(objName: Binding<String>, text: Binding<String>, title: String) {
        self._objName = objName
        self._text = text
        self.title = title
        let _ = print("SourceView.init")
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

//            ScrollView {
//                Text("\(text)")
//                    .monospaced()
//                    .textSelection(.enabled)
//                    .lineLimit(nil)
//                    .multilineTextAlignment(.leading)
//                    .frame(maxWidth: .infinity)
//            }
//            CodeEditor(source: $text, language: .pgsql, theme: .atelierDuneLight, flags: [.selectable, .editable], autoscroll: false, wordWrap: .constant(true))
            
            CodeEditTextView($text, language: .sql, theme: sqlTheme, font: sourceFont, tabWidth: tabWidth, lineHeight: lineHeight, wrapLines: true, editorOverscroll: editorOverscroll, cursorPosition: $cursorPosition, isEditable: true)
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
