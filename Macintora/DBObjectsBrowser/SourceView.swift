//
//  SourceView.swift
//  Macintora
//
//  Created by Ilia Sazonov on 9/7/22.
//
//  Read-only PL/SQL source viewer used by the DB Browser for packages, package
//  bodies, standalone procedures/functions, types and triggers. Left rail is a
//  navigable code outline (`CodeOutlineView`); the rail is collapsible (toolbar
//  toggle, persisted) and resizable (split divider).
//

import SwiftUI

struct SourceView: View {
    @Binding var objName: String
    @Binding var text: String
    @State var title: String
    @State private var selection: Range<String.Index> = "".startIndex..<"".endIndex
    @AppStorage("dbSourceOutlineVisible") private var showOutline = true

    init(objName: Binding<String>, text: Binding<String>, title: String) {
        self._objName = objName
        self._text = text
        self.title = title
    }

    var body: some View {
        HSplitView {
            if showOutline {
                CodeOutlineView(source: $text,
                                selection: $selection,
                                accessibilityIdentifier: "outline.db.source")
                    .frame(minWidth: 200, idealWidth: 280, maxWidth: .infinity)
            }

            VStack {
                HStack {
                    Button("Toggle Outline", systemImage: "sidebar.left") {
                        showOutline.toggle()
                    }
                    .labelStyle(.iconOnly)
                    .help(showOutline ? "Hide the symbol outline" : "Show the symbol outline")

                    Text(title)
                        .font(.title2)
                        .frame(alignment: .leading)

                    Spacer()

                    Button {
                        let formatter = Formatter()
                        formatter.formattedSource = "...formatting, please wait..."

                        SwiftUIWindow.open { window in
                            let _ = (window.title = objName)   // swiftlint:disable:this redundant_discardable_let
                            FormattedView(formatter: formatter, onDone: { window.close() })
                        }
                        .closeOnEscape(true)

                        Task { [objName, text] in
                            let formatted = await formatter.formatSource(name: objName, text: text)
                            formatter.formattedSource = formatted
                        }
                    }
                    label: { Text("Format & View") }

                    Button {
                        let formatter = Formatter()
                        formatter.formattedSource = "...formatting, please wait..."
                        Task { [self, text] in
                            _ = await formatter.formatSource(name: objName, text: text)
                        }
                    }
                    label: { Text("Format & Save") }
                        .disabled(true)
                }

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
                .frame(maxWidth: .infinity, minHeight: 100, idealHeight: 300,
                       maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(minWidth: 360)
        }
        .onChange(of: text) {
            // Switching DB objects swaps `text` out from under the same view —
            // drop the stale caret so it doesn't point past the new source.
            selection = text.startIndex ..< text.startIndex
        }
    }
}
