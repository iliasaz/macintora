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
                Button("New Tab") {
                    let doc = try! NSDocumentController.shared.makeUntitledDocument(ofType: NSDocumentController.shared.defaultType!)
                    NSDocumentController.shared.addDocument(doc)
                    doc.makeWindowControllers()
                    doc.windowControllers.first?.window?.tabbingMode = .preferred
                    doc.showWindows()
                }
                    .keyboardShortcut("t", modifiers: [.command])
            }
        }
        
        WindowGroup(for: DBCacheInputValue.self) { $value in
//            DBCacheBrowserMainView(input: value ?? .preview())
//            DBCacheMainView(input: value ?? .preview())
            let v = value ?? .preview()
            let cache = DBCacheVM(connDetails: v.mainConnection.mainConnDetails, selectedObjectName: v.selectedObjectName)
            DBCacheMainView(cache: cache)
                .environment(\.managedObjectContext, cache.persistenceController.container.viewContext)
        }
        
        WindowGroup(for: SBInputValue.self) { $value in
            SBMainView(inputValue: value ?? .preview())
        }
        
        Settings {
            SettingsView()
        }
    }
}

struct MainDocumentMenuCommands: Commands {
//    @FocusedValue(\.cacheConnectionDetails) var cacheConnectionDetails: ConnectionDetails?
    @FocusedValue(\.selectedObjectName) var selectedObjectName: String?
    @FocusedValue(\.mainConnection) var mainConnection
    @ObservedObject var appSettings: AppSettings
    @Environment(\.openWindow) var openWindow

    var body: some Commands {
        CommandMenu("Database") {
//            NavigationLink("DB Browser", destination: DBCacheBrowserMainView(connDetails: cacheConnectionDetails ?? ConnectionDetails(), selectedObjectName: selectedObjectName)
//                .environmentObject(appSettings)
//                .frame(minWidth: 400, idealWidth: 1200, maxWidth: .infinity, minHeight: 400, idealHeight: 1000, maxHeight: .infinity)
//            )
//                .disabled(cacheConnectionDetails == nil)
//                .presentedWindowStyle(TitleBarWindowStyle())
//                .keyboardShortcut("d", modifiers: [.command])
            Button("Database Browser") {
                openWindow(value: DBCacheInputValue(mainConnection: mainConnection ?? .preview(), selectedObjectName: selectedObjectName))
            }
            .disabled(mainConnection?.mainConnDetails == nil)
                .presentedWindowStyle(TitleBarWindowStyle())
                .keyboardShortcut("d", modifiers: [.command])
            
            
//            NavigationLink("Session Browser", destination: SBMainView(connDetails: sbConnDetails ?? .preview())
//                .environmentObject(appSettings)
//                .frame(minWidth: 400, idealWidth: 1200, maxWidth: .infinity, minHeight: 400, idealHeight: 1000, maxHeight: .infinity)
//            )
//                .disabled(cacheConnectionDetails == nil)
//                .presentedWindowStyle(TitleBarWindowStyle())
//                .keyboardShortcut("s", modifiers: [.command, .control, .shift])

            Button("Session Browser") {
                log.viewCycle.debug("Opening SB with mainConnection: \(mainConnection?.description ?? "no main connection")")
                openWindow(value: SBInputValue(mainConnection: mainConnection ?? .preview()))
            }
            .disabled(mainConnection?.mainConnDetails == nil)
                .presentedWindowStyle(TitleBarWindowStyle())
                .keyboardShortcut("s", modifiers: [.command, .control, .shift])
        }
    }
}


//struct DocumentFocusedKey: FocusedValueKey {
//    typealias Value = ConnectionDetails
//}

struct SelectedObjectNameKey: FocusedValueKey {
    typealias Value = String
}

struct MainConnectionKey: FocusedValueKey {
    typealias Value = MainConnection
}


extension FocusedValues {
//    var cacheConnectionDetails: ConnectionDetails? {
//        get {
//            self[DocumentFocusedKey.self]
//        }
//        set {
//            self[DocumentFocusedKey.self] = newValue
//        }
//    }
    
    var selectedObjectName: SelectedObjectNameKey.Value? {
        get {
            self[SelectedObjectNameKey.self]
        }
        set {
            self[SelectedObjectNameKey.self] = newValue
        }
    }
    
    var mainConnection: MainConnectionKey.Value? {
        get {
            self[MainConnectionKey.self]
        }
        set {
            self[MainConnectionKey.self] = newValue
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

//public func toggleSidebar() {
//    NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
//}
