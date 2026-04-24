//
//  MacintoraEditor.swift
//  Macintora
//
//  SwiftUI wrapper around `STTextView` (TextKit 2). The public API is shaped to
//  match the call sites that used `CodeEditor` before the migration: a plain
//  `Binding<String>` for the document text and a `Binding<Range<String.Index>>`
//  for the selection so downstream features (`getCurrentSql(for:)`, `format(of:)`,
//  `runCurrentSQL(for:)`, etc.) keep their existing signatures.
//
//  Phase 1 intentionally installs no plugins; NeonPlugin / syntax highlighting
//  is added in Phase 3.
//

import AppKit
import SwiftUI
import STTextView
import STPluginNeon

struct MacintoraEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: Range<String.Index>
    let language: EditorLanguage
    let isEditable: Bool
    let isSelectable: Bool
    @Binding var wordWrap: Bool
    let showsLineNumbers: Bool
    let highlightsSelectedLine: Bool
    let accessibilityIdentifier: String

    init(
        text: Binding<String>,
        selection: Binding<Range<String.Index>>,
        language: EditorLanguage = .sql,
        isEditable: Bool = true,
        isSelectable: Bool = true,
        wordWrap: Binding<Bool> = .constant(false),
        showsLineNumbers: Bool = true,
        highlightsSelectedLine: Bool = true,
        accessibilityIdentifier: String = "editor.main"
    ) {
        self._text = text
        self._selection = selection
        self.language = language
        self.isEditable = isEditable
        self.isSelectable = isSelectable
        self._wordWrap = wordWrap
        self.showsLineNumbers = showsLineNumbers
        self.highlightsSelectedLine = highlightsSelectedLine
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selection: $selection)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = STTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? STTextView else {
            return scrollView
        }

        textView.textDelegate = context.coordinator
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.isEditable = isEditable
        textView.isSelectable = isSelectable
        textView.showsLineNumbers = showsLineNumbers
        textView.highlightSelectedLine = highlightsSelectedLine
        textView.isHorizontallyResizable = !wordWrap
        textView.setAccessibilityIdentifier(accessibilityIdentifier)
        textView.setAccessibilityRole(.textArea)

        // Install the Neon syntax-highlighting plugin before the first text
        // assignment so the initial parse fires on the seeded content.
        textView.addPlugin(language.neonPlugin())

        // Seed initial content without echoing the change back into the binding.
        context.coordinator.isApplyingExternalUpdate = true
        textView.text = text
        if let range = EditorSelectionBridge.nsRange(for: selection, in: text) {
            textView.textSelection = range
        }
        context.coordinator.isApplyingExternalUpdate = false

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? STTextView else { return }

        if textView.isEditable != isEditable { textView.isEditable = isEditable }
        if textView.isSelectable != isSelectable { textView.isSelectable = isSelectable }
        if textView.showsLineNumbers != showsLineNumbers { textView.showsLineNumbers = showsLineNumbers }
        if textView.highlightSelectedLine != highlightsSelectedLine {
            textView.highlightSelectedLine = highlightsSelectedLine
        }
        if textView.isHorizontallyResizable == wordWrap {
            textView.isHorizontallyResizable = !wordWrap
        }

        // Only overwrite editor contents when the upstream text diverged from what
        // the editor already shows. Skipping the no-op write prevents the classic
        // re-entrancy loop where a keystroke-driven binding update would stomp on
        // the partially-applied character and lose input. The `Mutex` guard in
        // `MainDocumentVM` relies on this exact contract.
        if textView.text != text {
            context.coordinator.isApplyingExternalUpdate = true
            textView.text = text
            context.coordinator.isApplyingExternalUpdate = false
        }

        if let newRange = EditorSelectionBridge.nsRange(for: selection, in: text),
           textView.textSelection != newRange,
           !context.coordinator.isPushingSelection {
            textView.textSelection = newRange
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        if let textView = scrollView.documentView as? STTextView {
            textView.textDelegate = nil
        }
    }
}
