//
//  MacOraDocumentView.swift
//  MacOra
//
//  Created by Ilia Sazonov on 10/4/21.
//

import SwiftUI
import CodeEditor
import Logging
import Combine
import AppKit

public enum FocusedView: Int, Hashable {
    case codeEditor, grid, login, connectionList
}

struct MainDocumentView: View {
    @ObservedObject var document: MainDocumentVM
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.undoManager) var undoManager
    @State private var selectedTab: String = "queryResults"
    @FocusState private var focusedView: FocusedView?
    @Environment(\.openDocument) private var openDocument
    @AppStorage("wordWrap") private var wordWrapping = false

    @StateObject private var resultsController: ResultsController
    @State private var editorSelection: Range<String.Index> = "".startIndex..<"".endIndex
    
    var selectedObject: String {
        if editorSelection.isEmpty { return "" }
        let s = String(document.model.text[editorSelection])
        if s.count > 128 { return "" }
        return s
    }
    
    init(document: MainDocumentVM) {
        self.document = document
        _resultsController = StateObject(wrappedValue: document.resultsController!)
    }
    
    var body: some View {
        NavigationSplitView {
            ConnectionListView(
                connectionStatus: $document.isConnected,
                username: $document.mainConnection.mainConnDetails.username,
                password: $document.mainConnection.mainConnDetails.password,
                selectedTns: Binding<String> ( get: { document.mainConnection.mainConnDetails.tns }, set: {document.mainConnection.mainConnDetails.tns = $0} ),
                connectionRole: $document.mainConnection.mainConnDetails.connectionRole,
                connect: document.connect,
                disconnect: document.disconnect
            )
        } detail: {
            VStack {
                VSplitView {
                    CodeEditor(source: $document.model.text,
                               selection: $editorSelection,
                               language: .pgsql,
                               theme: .atelierDuneLight,
                               indentStyle: .softTab(width: 2),
                               autoPairs: [ "{": "}", "(": ")" ],
                               inset: CGSize(width: 8, height: 8),
                               autoscroll: false, wordWrap: $wordWrapping
                    )
                        .frame(maxWidth: .infinity, minHeight:100, maxHeight: .infinity)
                        .focused($focusedView, equals: .codeEditor)
                        .layoutPriority(1)
                    
                    ResultViewWrapper(resultsController: resultsController)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusedSceneValue(\.mainConnection, document.mainConnection)
        .focusedSceneValue(\.selectedObjectName, selectedObject)
        .onAppear {
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
                        document.connect()
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
                
                Toggle("Word Wrap", isOn: $wordWrapping)
                    .toggleStyle(.switch)
                    .help("Word Wrap")
            }
        }
    }
}





struct MacOraDocumentView_Previews: PreviewProvider {
    static var previews: some View {
        MainDocumentView(document: MainDocumentVM())
            .frame(width: 1000.0, height: 600.0, alignment: .center)
            .environmentObject(AppSettings.shared)
    }
}

