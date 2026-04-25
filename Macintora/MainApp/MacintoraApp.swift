//
//  MacOraApp.swift
//  MacOra
//
//  Created by Ilia Sazonov on 10/4/21.
//

import SwiftUI
import Combine
import os
import UniformTypeIdentifiers
import OracleNIO

extension Logger {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.iliasazonov.macintora"

    /// Logs the view cycles like viewDidLoad.
    var viewCycle: Logger { Logger(subsystem: Logger.subsystem, category: "viewcycle") }
    var `default`: Logger { Logger(subsystem: Logger.subsystem, category: "default") }
}

let log = Logger().default

/// Forces the app to always open an Untitled document on launch (instead of
/// showing the `NSOpenPanel` picker that macOS's default DocumentGroup flow
/// presents when nothing was opened from launch args). Positional file args
/// still open normally because NSApp's file-open handling fires earlier than
/// `applicationShouldOpenUntitledFile`. This also means integration tests
/// never see a picker — the host app comes up on an Untitled doc the tests can
/// ignore.
final class MacintoraAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders: on some macOS versions the "Show Open panel at
        // startup" behaviour is driven by this global default rather than the
        // delegate method below. Registering a default of NO doesn't override
        // a user's explicit preference — it just changes the *default*.
        UserDefaults.standard.register(defaults: [
            "NSShowAppCentricOpenPanelInsteadOfUntitledFile": false
        ])
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // Always open an Untitled document when no file was handed to us on
        // launch. Never show the Open panel.
        true
    }
}

@main
struct MacOraApp: App {
    @NSApplicationDelegateAdaptor(MacintoraAppDelegate.self) var appDelegate

    @State private var connectionStore = ConnectionStore()
    private let keychainService = KeychainService()

    var body: some Scene {
        DocumentGroup(newDocument: { MainDocumentVM() }) { config in
            MainDocumentView(document: config.document)
                .frame(minWidth: 600, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
                .environment(\.connectionStore, connectionStore)
                .environment(\.keychainService, keychainService)
        }
        .defaultSize(width: 1100, height: 700)
        .handlesExternalEvents(matching: ["file"])
        .commands {
            SidebarCommands()
            ToolbarCommands()
            MainDocumentMenuCommands()
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
            let v = value ?? .preview()
            let cache = DBCacheVM(connDetails: v.mainConnection.mainConnDetails, selectedObjectName: v.selectedObjectName)
            DBCacheMainView(cache: cache)
                .environment(\.managedObjectContext, cache.persistenceController.container.viewContext)
                .environment(\.connectionStore, connectionStore)
                .environment(\.keychainService, keychainService)
        }

        WindowGroup(for: SBInputValue.self) { $value in
            SBMainView(inputValue: value ?? .preview())
                .environment(\.connectionStore, connectionStore)
                .environment(\.keychainService, keychainService)
        }

        Settings {
            SettingsView()
                .environment(\.connectionStore, connectionStore)
                .environment(\.keychainService, keychainService)
        }
    }
}

struct MainDocumentMenuCommands: Commands {
//    @FocusedValue(\.cacheConnectionDetails) var cacheConnectionDetails: ConnectionDetails?
    @FocusedValue(\.selectedObjectName) var selectedObjectName: String?
    @FocusedValue(\.mainConnection) var mainConnection
    @Environment(\.openWindow) var openWindow

    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandMenu("Database") {
            Button("Manage Connections…") {
                openSettings()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Divider()

            Button("Database Browser") {
                openWindow(value: DBCacheInputValue(mainConnection: mainConnection ?? .preview(), selectedObjectName: selectedObjectName))
            }
            .disabled(mainConnection?.mainConnDetails == nil)
                .presentedWindowStyle(TitleBarWindowStyle())
                .keyboardShortcut("d", modifiers: [.command])

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

//public func toggleSidebar() {
//    NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
//}
