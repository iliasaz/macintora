//
//  MacOraDocumentView.swift
//  MacOra
//
//  Created by Ilia Sazonov on 10/4/21.
//

import SwiftUI
import Combine
import AppKit

public enum FocusedView: Int, Hashable {
    case codeEditor, grid, login, connectionList
}

struct MainDocumentView: View {
    @ObservedObject var document: MainDocumentVM
    @Environment(\.undoManager) var undoManager
    @Environment(\.connectionStore) private var injectedStore
    @Environment(\.keychainService) private var keychain
    @State private var selectedTab: String = "queryResults"
    @FocusState private var focusedView: FocusedView?
    @Environment(\.openDocument) private var openDocument
    @AppStorage("wordWrap") private var wordWrapping = false

    private var store: ConnectionStore {
        guard let injectedStore else {
            preconditionFailure("ConnectionStore not installed in environment — wire it from MacOraApp.body")
        }
        return injectedStore
    }

    @State private var resultsController: ResultsController
    @State private var editorSelection: Range<String.Index> = "".startIndex..<"".endIndex

    var selectedObject: String {
        if editorSelection.isEmpty { return "" }
        let s = String(document.model.text[editorSelection])
        if s.count > 128 { return "" }
        return s
    }

    init(document: MainDocumentVM) {
        self.document = document
        // `MainDocumentVM`'s init is nonisolated (to satisfy the
        // ReferenceFileDocument protocol witness), so it doesn't create a
        // ResultsController itself. We create it here on the main actor —
        // SwiftUI guarantees this view initializer runs on MainActor — and
        // hand the same instance back to the document so the VM's intent
        // methods can drive it too.
        let controller = document.resultsController ?? ResultsController(document: document)
        document.attachResultsController(controller)
        _resultsController = State(wrappedValue: controller)
    }
    
    var body: some View {
        NavigationSplitView {
            // Wrap in `ScrollView` to stabilise NavigationSplitView's safe-area
            // inset propagation. Without it, toggling the sidebar drove
            // `_NSSplitViewItemViewWrapper.updateConstraints` into an
            // infinite loop ("more Update Constraints in Window passes than
            // there are views in the window") which crashed the app —
            // regression covered by `SidebarToggleCrashRegressionTests`.
            ScrollView {
                ConnectionListView(
                    connectionStatus: $document.isConnected,
                    details: $document.mainConnection.mainConnDetails,
                    connect: { document.connect(store: store, keychain: keychain) },
                    disconnect: document.disconnect
                )
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 420)
        } detail: {
            VStack {
                VSplitView {
                    MacintoraEditor(
                        text: $document.model.text,
                        selection: $editorSelection,
                        language: .sql,
                        isEditable: true,
                        isSelectable: true,
                        wordWrap: $wordWrapping,
                        showsLineNumbers: true,
                        highlightsSelectedLine: true
                    )
                        .frame(maxWidth: .infinity, minHeight: 120, idealHeight: 320, maxHeight: .infinity)
                        .focused($focusedView, equals: .codeEditor)

                    ResultViewWrapper(
                        resultsController: resultsController,
                        onRevealSource: { utf16Range in
                            if let range = EditorSelectionBridge.range(forUTF16: utf16Range, in: document.model.text) {
                                editorSelection = range
                                focusedView = .codeEditor
                            }
                        }
                    )
                    .frame(maxWidth: .infinity, minHeight: 200, idealHeight: 280, maxHeight: .infinity)
                    .modifier(SubstitutionSheetModifier(controller: resultsController))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            WindowLayoutPersister(
                windowAutosaveName: "Macintora.MainDocument",
                splitAutosavePrefix: "Macintora.MainDocument.split"
            )
            .frame(width: 0, height: 0)
        )
        .focusedSceneValue(\.mainConnection, document.mainConnection)
        .focusedSceneValue(\.selectedObjectName, selectedObject)
        .tnsImportPromptOnFirstLaunch()
        .onAppear {
            document.prepareOnAppear(store: injectedStore, keychain: keychain)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                self.focusedView = .codeEditor
            }
        }
        
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                // connect / disconnect
                Button {
                    if document.isConnected == .connected {
                        document.disconnect()
                    } else {
                        document.connect(store: store, keychain: keychain)
                    }
                    focusedView = .codeEditor
                } label: {
                    if document.isConnected == .connected {
                        Image(systemName: "wifi").foregroundColor(Color.green)
                    } else if document.isConnected == .disconnected {
                        Image(systemName: "wifi.slash").foregroundColor(Color.red)
                    } else {
                        Image(systemName: "wifi").foregroundColor(Color.orange)
                    }
                }
                .disabled(document.isConnected == .changing)
                .help(document.isConnected == .disconnected ? "Connect" : "Disconnect")
                .accessibilityIdentifier(document.isConnected == .connected ? "toolbar.disconnect" : "toolbar.connect")
                .accessibilityLabel(document.isConnected == .connected ? "Disconnect" : "Connect")

                // execute/stop sql
                Button {
                    if document.resultsController?.isExecuting ?? false {
                        document.stopRunningSQL()
                    } else {
                        document.runCurrentSQL(for: editorSelection)
                    }
                    focusedView = .codeEditor
                } label: {
                    if document.resultsController?.isExecuting ?? false {
                        Image(systemName: "stop").foregroundColor(Color.red)
                    } else if document.isConnected == .connected && document.resultsController?.isExecuting == false {
                        Image(systemName: "play").foregroundColor(Color.green)
                    } else {
                        Image(systemName: "play")
                    }
                }
                .disabled(document.isConnected != .connected)
                .keyboardShortcut(document.resultsController?.isExecuting ?? false ? "b" : "r", modifiers: .command)
                .help("Execute current statement")
                .accessibilityIdentifier("toolbar.run")
                .accessibilityLabel("Run")

                // run script (whole file)
                Button {
                    if document.resultsController?.isExecuting ?? false {
                        document.stopRunningSQL()
                    } else {
                        document.runScript()
                    }
                    focusedView = .codeEditor
                } label: { Image(systemName: "play.square") }
                    .disabled(document.isConnected != .connected)
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .help("Run entire script")
                    .accessibilityIdentifier("toolbar.runScript")
                    .accessibilityLabel("Run Script")

                // run from cursor / run selection
                Button {
                    if document.resultsController?.isExecuting ?? false {
                        document.stopRunningSQL()
                    } else if !editorSelection.isEmpty {
                        document.runScriptSelection(editorSelection)
                    } else {
                        document.runScriptFromCursor(editorSelection.lowerBound)
                    }
                    focusedView = .codeEditor
                } label: { Image(systemName: "play.square.stack") }
                    .disabled(document.isConnected != .connected)
                    .keyboardShortcut("r", modifiers: [.command, .option])
                    .help(editorSelection.isEmpty ? "Run script from cursor" : "Run selection as script")
                    .accessibilityIdentifier("toolbar.runScriptFromCursor")
                    .accessibilityLabel("Run From Cursor")

                // explain plan
                Button {
                    if !(document.resultsController?.isExecuting ?? false) {
                        document.explainPlan(for: editorSelection)
                    }
                    focusedView = .codeEditor
                } label: {
                    Image(systemName: "list.number")
                }
                .disabled(document.isConnected != .connected || document.resultsController?.isExecuting ?? false)
                .keyboardShortcut("e", modifiers: .command)
                .help("Explain plan of current statement")
                
                // copy current sql into a new tab
                Button {
                    Task {
                        if let url = document.newDocument(from: editorSelection) {
                            let (doc,_): (NSDocument, Bool) = try await NSDocumentController.shared.openDocument(withContentsOf: url, display: false)
                            NSDocumentController.shared.addDocument(doc)
                            doc.makeWindowControllers()
                            doc.windowControllers.first?.window?.tabbingMode = .preferred
                            doc.showWindows()
                        }
                    }
                } label: { Image(systemName: "doc.on.doc") }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                    .help("New Tab")
                
                // format sql
                Button {
                    document.format(of: $editorSelection)
                    focusedView = .codeEditor
                } label: { Image(systemName: "wand.and.stars") }
                    .keyboardShortcut("f", modifiers: [.command, .control])
                    .help("Format")
                
                // compile source
                Button {
                    document.compileSource(for: editorSelection)
                    focusedView = .codeEditor
                } label: { Image(systemName: "ellipsis.curlybraces") }
                    .disabled(document.isConnected != .connected || document.resultsController?.isExecuting ?? false)
                    .keyboardShortcut("c", modifiers: [.command, .option])
                    .help("Compile")
                
                Spacer()

                Button {
                    document.ping()
                } label: {
                    switch document.connectionHealth {
                        case .notConnected:
                            Image(systemName: "hand.thumbsup").foregroundColor(Color.gray)
                        case .ok:
                            Image(systemName: "hand.thumbsup").foregroundColor(Color.green)
                        case .lost:
                            Image(systemName: "hand.thumbsdown.fill").foregroundColor(Color.red)
                        case .busy:
                            Image(systemName: "hand.thumbsup.fill").foregroundColor(Color.orange)
                    }
                }
                .help("Ping")
              Spacer()

                Toggle("Word Wrap", isOn: $wordWrapping)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Word Wrap")
            }
        }
    }
}





/// Owns the substitution-prompt sheet binding via `@Bindable` so SwiftUI can
/// track stable identity for `pendingSubstitution`. A `Binding(get:set:)`
/// closure-based binding here was triggering an Auto Layout invalidation
/// loop inside the surrounding `NavigationSplitView` / `VSplitView`.
private struct SubstitutionSheetModifier: ViewModifier {
    @Bindable var controller: ResultsController

    func body(content: Content) -> some View {
        content.sheet(item: $controller.pendingSubstitution) { request in
            SubstitutionInputView(request: request) { values in
                controller.resolvePendingSubstitution(values)
            }
        }
    }
}


struct MacOraDocumentView_Previews: PreviewProvider {
    static var previews: some View {
        MainDocumentView(document: MainDocumentVM())
            .frame(width: 1000.0, height: 600.0, alignment: .center)
    }
}

