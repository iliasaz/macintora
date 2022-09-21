//
//  MacOraDocumentView.swift
//  MacOra
//
//  Created by Ilia Sazonov on 10/4/21.
//

import SwiftUI
import CodeEditor
import Logging

public enum FocusedView: Int, Hashable {
    case codeEditor, grid, login, connectionList
}

struct MainDocumentView: View {
    @ObservedObject var document: MainDocumentVM
    @EnvironmentObject var appSettings: AppSettings
    @State private var selectedTab: String = "queryResults"
    @FocusState private var focusedView: FocusedView?

    @StateObject private var resultsController: ResultsController
    @State private var editorSelection: Range<String.Index> = "".startIndex..<"".endIndex
    
    var selectedText: String {
        if editorSelection.isEmpty { return "" }
        return String(document.model.text[editorSelection])
    }
    
    init(document: MainDocumentVM) {
        self.document = document
        _resultsController = StateObject(wrappedValue: document.resultsController!)
    }
    
    var body: some View {
        NavigationView {
            ConnectionListView(
                connectionSatus: $document.isConnected,
                username: $document.connDetails.username,
                password: $document.connDetails.password,
                selectedTns: Binding<String> ( get: { document.connDetails.tns }, set: {document.connDetails.tns = $0} ),
                connectionRole: $document.connDetails.connectionRole,
                connect: document.connect,
                disconnect: document.disconnect
            )
            VStack {
                GeometryReader { geo in
                    VSplitView {
                        CodeEditor(source: $document.model.text,
                                   selection: $editorSelection,
                                   language: .pgsql,
                                   theme: .atelierDuneLight,
                                   autoPairs: [ "{": "}", "(": ")" ],
                                   inset: CGSize(width: 8, height: 8),
                                   autoscroll: false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .focused($focusedView, equals: .codeEditor)
                        
                        ResultViewWrapper(resultsController: resultsController)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .focusedSceneValue(\.cacheConnectionDetails, document.connDetails )
        .focusedSceneValue(\.selectedObjectName, selectedText )
        .focusedSceneValue(\.sbConnDetails, document.sbConnDetails )
        .onAppear {
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
              self.focusedView = .codeEditor
          }
        }
        
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: toggleSidebar, label: {
                    Image(systemName: "sidebar.left")
                } )
                .help("Sidebar")
            }
            
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
                .keyboardShortcut("r", modifiers: .command)
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
                
                // open a new window
                Button {
                    Task {
                        if let url = document.newDocument(from: editorSelection) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } label: { Image(systemName: "doc.on.doc") }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .help("Clone")
                
                // format sql
                Button {
                    document.format(of: editorSelection)
                    editorSelection = editorSelection.lowerBound..<editorSelection.lowerBound
                    focusedView = .codeEditor
                } label: { Image(systemName: "wand.and.stars") }
                    .keyboardShortcut("f", modifiers: [.control])
                    .help("Format")
                
                // compile source
                Button {
                    document.compileSource()
                    focusedView = .codeEditor
                } label: { Image(systemName: "ellipsis.curlybraces") }
                    .disabled(document.isConnected != .connected || document.resultsController?.isExecuting ?? false)
                    .keyboardShortcut("c", modifiers: [.command, .option])
                    .help("Compile")
                
                Spacer()
            }
            
            ToolbarItemGroup(placement: .confirmationAction) {
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
                
                Button(action: appSettings.setCurrentTheme, label: {
                    Image(systemName: AppSettings.shared.currentTheme == .light ? "moon" : "moon.fill")
                })
                .help("Theme")
                
                Button(action: {
                    NSApplication.shared.terminate(self)
                }, label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                })
                .help("Exit")
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

