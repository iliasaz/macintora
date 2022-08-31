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
//    @FocusedBinding(\.dbCache) var dbCache

    var body: some Scene {

        DocumentGroup(newDocument: { MainDocumentVM() }) { config in
                MainDocumentView(document: config.document)
                    .preferredColorScheme(appSettings.currentTheme.colorScheme)
                    .environmentObject(appSettings)
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

        WindowGroup {
//            let cacheConnectionDetails = CacheConnectionDetails(from: ConnectionDetails())
            let cacheConnectionDetails = ConnectionDetails()
            DBCacheBrowserMainView(connDetails: cacheConnectionDetails)
                .preferredColorScheme(appSettings.currentTheme.colorScheme)
                .environmentObject(appSettings)
        }
        .handlesExternalEvents(matching: ["dbBrowser"])
        .commands {
            SidebarCommands()
            ToolbarCommands()
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
    @FocusedBinding(\.cacheConnectionDetails) var cacheConnectionDetails: ConnectionDetails?
    @ObservedObject var appSettings: AppSettings

    var body: some Commands {
        CommandMenu("Database") {
            NavigationLink("Browser", destination: DBCacheBrowserMainView(connDetails: cacheConnectionDetails ?? ConnectionDetails())
                .preferredColorScheme(appSettings.currentTheme.colorScheme)
                .environmentObject(appSettings)
            )
                .disabled(cacheConnectionDetails == nil)
                .presentedWindowStyle(TitleBarWindowStyle())
                .keyboardShortcut("d", modifiers: .command)
        }
    }
}


struct DocumentFocusedKey: FocusedValueKey {
    typealias Value = Binding<ConnectionDetails>
}

extension FocusedValues {
    var cacheConnectionDetails: Binding<ConnectionDetails>? {
        get {
            self[DocumentFocusedKey.self]
        }
        set {
            self[DocumentFocusedKey.self] = newValue
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
