//
//  MacOraApp.swift
//  MacOra
//
//  Created by Ilia Sazonov on 10/4/21.
//

import SwiftUI
import os
import UniformTypeIdentifiers
import SwiftOracle

extension Logger {
    static var subsystem = Bundle.main.bundleIdentifier!
    
    /// Logs the view cycles like viewDidLoad.
    var viewCycle: Logger { Logger(subsystem: Logger.subsystem, category: "viewcycle") }
    var `default`: Logger { Logger(subsystem: Logger.subsystem, category: "default") }
}

let log = Logger().default

@main
struct MacOraApp: App {
    @StateObject var appStateContainer = AppStateContainer()
    @ObservedObject var appSettings = AppSettings.shared
    
    var body: some Scene {
        DocumentGroup(newDocument: { MainDocumentVM() }) { config in
                MainDocumentView(document: config.document)
                    .environmentObject(appSettings)
                    .frame(minWidth: 400, idealWidth: 1600, maxWidth: .infinity, minHeight: 400, idealHeight: 1000, maxHeight: .infinity)
            
        }
        .handlesExternalEvents(matching: ["file"])
        .commands {
            SidebarCommands()
            ToolbarCommands()
            MainDocumentMenuCommands(appSettings: appSettings)
            TextEditingCommands()
            CommandGroup(after: .newItem) {
                Button(action: {
                    if let currentWindow = NSApp.keyWindow,
                       let windowController = currentWindow.windowController {
                        windowController.newWindowForTab(nil)
                        if let newWindow = NSApp.keyWindow,
                           currentWindow != newWindow {
                            currentWindow.addTabbedWindow(newWindow, ordered: .above)
                        }
                    }
                }) {
                    Text("New Tab")
                }
                .keyboardShortcut("t", modifiers: [.command])
            }
        }
        
        Settings {
            SettingsView()
        }
    }
}

struct MainDocumentMenuCommands: Commands {
    @FocusedValue(\.cacheConnectionDetails) var cacheConnectionDetails: ConnectionDetails?
    @FocusedValue(\.selectedObjectName) var selectedObjectName: String?
    @FocusedValue(\.sbConnDetails) var sbConnDetails: SBConnDetails?
    @ObservedObject var appSettings: AppSettings

    var body: some Commands {
        CommandMenu("Database") {
            NavigationLink("DB Browser", destination: DBCacheBrowserMainView(connDetails: cacheConnectionDetails ?? ConnectionDetails(), selectedObjectName: selectedObjectName)
                .environmentObject(appSettings)
                .frame(minWidth: 400, idealWidth: 1200, maxWidth: .infinity, minHeight: 400, idealHeight: 1000, maxHeight: .infinity)
            )
                .disabled(cacheConnectionDetails == nil)
                .presentedWindowStyle(TitleBarWindowStyle())
                .keyboardShortcut("d", modifiers: [.command])
            
            NavigationLink("Session Browser", destination: SBMainView(connDetails: sbConnDetails ?? .preview())
                .environmentObject(appSettings)
                .frame(minWidth: 400, idealWidth: 1200, maxWidth: .infinity, minHeight: 400, idealHeight: 1000, maxHeight: .infinity)
            )
                .disabled(cacheConnectionDetails == nil)
                .presentedWindowStyle(TitleBarWindowStyle())
                .keyboardShortcut("s", modifiers: [.command, .control, .shift])
        }
    }
}


struct DocumentFocusedKey: FocusedValueKey {
    typealias Value = ConnectionDetails
}

struct SelectedObjectNameKey: FocusedValueKey {
    typealias Value = String
}

struct SBConnDetailsKey: FocusedValueKey {
    typealias Value = SBConnDetails
}


extension FocusedValues {
    var cacheConnectionDetails: ConnectionDetails? {
        get {
            self[DocumentFocusedKey.self]
        }
        set {
            self[DocumentFocusedKey.self] = newValue
        }
    }
    
    var selectedObjectName: SelectedObjectNameKey.Value? {
        get {
            self[SelectedObjectNameKey.self]
        }
        set {
            self[SelectedObjectNameKey.self] = newValue
        }
    }
    
    var sbConnDetails: SBConnDetails? {
        get {
            self[SBConnDetailsKey.self]
        }
        set {
            self[SBConnDetailsKey.self] = newValue
        }
    }

}



class AppSettings: ObservableObject {
    static let shared = AppSettings()
    @AppStorage("currentTheme") var currentTheme: Theme = .unspecified
    
    init() {
        
    }
    
    func setCurrentTheme() {
        let currentTheme = AppSettings.shared.currentTheme
        AppSettings.shared.currentTheme = currentTheme == .light ? .dark : .light
    }
}

enum Theme: Int {
    case light
    case dark
    case unspecified
    
    var colorScheme: ColorScheme? {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        default: return nil
        }
    }
}

class AppStateContainer: ObservableObject {
    public var tnsReader = TnsReader()
}

public func toggleSidebar() {
    NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
}
