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
    /// Provides the current `MainConnection` at trigger time for the
    /// "Open in DB Browser" handler. Nil when the document has no connection.
    let mainConnectionProvider: (@MainActor () -> MainConnection?)?

    init(persistenceController: PersistenceController,
         defaultOwnerProvider: @escaping @MainActor () -> String,
         mainConnectionProvider: (@MainActor () -> MainConnection?)? = nil) {
        self.persistenceController = persistenceController
        self.defaultOwnerProvider = defaultOwnerProvider
        self.mainConnectionProvider = mainConnectionProvider
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
    let quickViewBox: EditorQuickViewBox?
    let openInBrowserBox: EditorOpenInBrowserBox?

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
        completionConfig: EditorCompletionConfig? = nil,
        quickViewBox: EditorQuickViewBox? = nil,
        openInBrowserBox: EditorOpenInBrowserBox? = nil
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
        self.quickViewBox = quickViewBox
        self.openInBrowserBox = openInBrowserBox
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
            completionConfig: completionConfig,
            quickViewBox: quickViewBox,
            openInBrowserBox: openInBrowserBox
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
    let quickViewBox: EditorQuickViewBox?
    let openInBrowserBox: EditorOpenInBrowserBox?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selection: $selection)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = MacintoraSTTextView.scrollableTextView()
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

        // Always create the SQLTreeStore and install Neon with a tree-update
        // callback, even when the host hasn't (yet) opted in to autocompletion.
        // The CompletionCoordinator is built lazily in `updateNSView` once
        // `completionConfig` arrives — typical for SwiftUI worksheets where
        // `.onAppear` builds the config AFTER `makeNSView` runs.
        let treeStore = SQLTreeStore()
        context.coordinator.treeStore = treeStore
        let onTreeUpdated: NeonPlugin.TreeUpdateHandler = { [weak treeStore] tree in
            treeStore?.update(tree)
        }
        if let config = completionConfig {
            context.coordinator.installCompletionCoordinator(with: config)
            context.coordinator.installQuickViewController(textView: textView)
            context.coordinator.bindQuickViewBox(quickViewBox, textView: textView)
            if let quickViewController = context.coordinator.quickViewController {
                textView.addPlugin(STDBObjectQuickViewPlugin(controller: quickViewController))
            }
            context.coordinator.wireOpenInBrowserHandler(
                openWindow: context.environment.openWindow,
                mainConnectionProvider: config.mainConnectionProvider)
            context.coordinator.bindOpenInBrowserBox(openInBrowserBox, textView: textView)
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

        // Promote a late-binding completion config (e.g. MainDocumentView's
        // `.onAppear` runs after `makeNSView`) to a live CompletionCoordinator
        // and Quick View plugin.
        if let config = completionConfig, context.coordinator.completionCoordinator == nil {
            context.coordinator.installCompletionCoordinator(with: config)
            context.coordinator.installQuickViewController(textView: textView)
            context.coordinator.bindQuickViewBox(quickViewBox, textView: textView)
            if let quickViewController = context.coordinator.quickViewController {
                textView.addPlugin(STDBObjectQuickViewPlugin(controller: quickViewController))
            }
            context.coordinator.wireOpenInBrowserHandler(
                openWindow: context.environment.openWindow,
                mainConnectionProvider: config.mainConnectionProvider)
            context.coordinator.bindOpenInBrowserBox(openInBrowserBox, textView: textView)
        } else {
            // Box identity may change on full document re-init. Rebind so menu
            // commands keep working against the freshly-mounted editor.
            if context.coordinator.quickViewBoxRef !== quickViewBox {
                context.coordinator.bindQuickViewBox(quickViewBox, textView: textView)
            }
            if context.coordinator.openInBrowserBoxRef !== openInBrowserBox {
                context.coordinator.bindOpenInBrowserBox(openInBrowserBox, textView: textView)
            }
        }

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
