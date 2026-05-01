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
//  `MacintoraEditor` is a thin SwiftUI `View` that reads the user's color theme
//  from `@AppStorage` and forwards it to `MacintoraEditorRepresentable`, the
//  underlying `NSViewRepresentable`. The `.id(editorTheme)` modifier forces a
//  full rebuild when the theme changes — required because `NeonPlugin` captures
//  its `Theme` once at setup and STTextView exposes no `removePlugin` hook.
//

import AppKit
import SwiftUI
import STTextView
import STPluginNeon

/// Per-editor configuration for autocompletion. Pass `nil` to opt out
/// (read-only viewers in DBBrowser etc.). The worksheet provides one tied
/// to the active connection's `PersistenceController` and username.
struct EditorCompletionConfig {
    let persistenceController: PersistenceController
    /// Closure so the editor picks up reconnects without rebuilding the view.
    let defaultOwnerProvider: @MainActor () -> String

    init(persistenceController: PersistenceController,
         defaultOwnerProvider: @escaping @MainActor () -> String) {
        self.persistenceController = persistenceController
        self.defaultOwnerProvider = defaultOwnerProvider
    }
}

struct MacintoraEditor: View {
    @Binding var text: String
    @Binding var selection: Range<String.Index>
    let language: EditorLanguage
    let isEditable: Bool
    let isSelectable: Bool
    @Binding var wordWrap: Bool
    let showsLineNumbers: Bool
    let highlightsSelectedLine: Bool
    let accessibilityIdentifier: String
    let completionConfig: EditorCompletionConfig?

    @AppStorage("editorTheme") private var editorThemeRaw: String = EditorTheme.default.rawValue

    init(
        text: Binding<String>,
        selection: Binding<Range<String.Index>>,
        language: EditorLanguage = .sql,
        isEditable: Bool = true,
        isSelectable: Bool = true,
        wordWrap: Binding<Bool> = .constant(false),
        showsLineNumbers: Bool = true,
        highlightsSelectedLine: Bool = true,
        accessibilityIdentifier: String = "editor.main",
        completionConfig: EditorCompletionConfig? = nil
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
        self.completionConfig = completionConfig
    }

    private var editorTheme: EditorTheme {
        EditorTheme(rawValue: editorThemeRaw) ?? .default
    }

    var body: some View {
        MacintoraEditorRepresentable(
            text: $text,
            selection: $selection,
            language: language,
            isEditable: isEditable,
            isSelectable: isSelectable,
            wordWrap: $wordWrap,
            showsLineNumbers: showsLineNumbers,
            highlightsSelectedLine: highlightsSelectedLine,
            accessibilityIdentifier: accessibilityIdentifier,
            theme: editorTheme,
            completionConfig: completionConfig
        )
        .id(editorTheme)
    }
}

struct MacintoraEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: Range<String.Index>
    let language: EditorLanguage
    let isEditable: Bool
    let isSelectable: Bool
    @Binding var wordWrap: Bool
    let showsLineNumbers: Bool
    let highlightsSelectedLine: Bool
    let accessibilityIdentifier: String
    let theme: EditorTheme
    let completionConfig: EditorCompletionConfig?

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

        // When the host opted in to autocompletion, build the completion
        // stack now and feed parse-tree updates from Neon directly into the
        // shared `SQLTreeStore`. This avoids running a second tree-sitter
        // parser inside the host process.
        let onTreeUpdated: NeonPlugin.TreeUpdateHandler?
        if let config = completionConfig {
            let treeStore = SQLTreeStore()
            let dataSource = CompletionDataSource(persistenceController: config.persistenceController)
            let coordinator = CompletionCoordinator(
                treeStore: treeStore,
                dataSource: dataSource,
                defaultOwnerProvider: config.defaultOwnerProvider)
            context.coordinator.completionCoordinator = coordinator
            onTreeUpdated = { [weak treeStore] tree in
                treeStore?.update(tree)
            }
        } else {
            onTreeUpdated = nil
        }

        // Install the Neon syntax-highlighting plugin before the first text
        // assignment so the initial parse fires on the seeded content.
        textView.addPlugin(language.neonPlugin(theme: theme.neonTheme(),
                                               onTreeUpdated: onTreeUpdated))

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
