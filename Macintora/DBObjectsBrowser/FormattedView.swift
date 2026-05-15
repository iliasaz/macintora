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
    /// Closure invoked by the Done button. The `SwiftUIWindow` host passes
    /// its close action so the view doesn't need an NSWindow reference.
    /// Optional so the existing call sites that haven't been migrated
    /// still compile, but every site in this app now wires it.
    var onDone: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            MacintoraEditor(
                text: $formatter.formattedSource,
                selection: $selection,
                language: .sql,
                isEditable: false,
                isSelectable: true,
                wordWrap: .constant(true),
                showsLineNumbers: true,
                accessibilityIdentifier: "editor.db.formatted"
            )
            actionBar
        }
        .frame(minWidth: 400, idealWidth: 1000, maxWidth: .infinity, minHeight: 400, idealHeight: 1000, maxHeight: .infinity)
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Copy SQL") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(formatter.formattedSource, forType: .string)
            }
            Button("Done") {
                onDone?()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(onDone == nil)
        }
        .padding(12)
        .background(.bar)
    }
}

//struct FormattedView_Previews: PreviewProvider {
//    static var previews: some View {
//        FormattedView()
//    }
//}
