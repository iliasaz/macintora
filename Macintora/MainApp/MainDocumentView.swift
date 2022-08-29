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
                selectedTns: Binding<String> ( get: { document.connDetails.tns ?? ""}, set: {document.connDetails.tns = $0} ),
                connectionRole: $document.connDetails.connectionRole,
                connect: document.connect,
                disconnect: document.disconnect
            )
            VStack {
                GeometryReader { geo in
                    VSplitView {
//                        let _ = log.viewCycle.debug("Redrawing split view, \($document.editorSelectionRange.wrappedValue)")
//                        let _ = Self._printChanges()
                        CodeEditor(source: $document.model.text,
                                   selection: $document.editorSelectionRange,
                                   language: .pgsql,
                                   theme: .atelierDuneLight,
                                   autoPairs: [ "{": "}", "(": ")" ],
                                   inset: CGSize(width: 8, height: 8),
                                   autoscroll: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .focused($focusedView, equals: .codeEditor)
                        
                        ResultViewWrapper(resultsController: resultsController)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .focusedSceneValue(\.cacheConnectionDetails, $document.connDetails )
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
                        document.runCurrentSQL()
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
                        document.explainPlan()
                    }
                    focusedView = .codeEditor
                } label: {
                    Image(systemName: "list.number")
                }
                .disabled(document.isConnected != .connected || document.resultsController?.isExecuting ?? false)
                .keyboardShortcut("e", modifiers: .command)
                .help("Explain plan of current statement")
                
                // Show DB Browser
                Button {
                    if let url = URL(string: "Macintora://dbBrowser") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "list.bullet.below.rectangle")
                }
                .help("Database Browser")
                
                // open a new window
                Button {
                    Task {
                        if let url = document.newDocument() {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } label: { Image(systemName: "doc.on.doc") }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .help("Clone")
                
                // format sql
                Button {
                    document.format()
                    focusedView = .codeEditor
                } label: { Image(systemName: "wand.and.stars") }
                    .keyboardShortcut("f", modifiers: [.control])
                    .help("Format")
                
                // compile source
                Button {
                    document.compileSource()
                    focusedView = .codeEditor
                } label: { Image(systemName: "ellipsis.curlybraces") }
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

