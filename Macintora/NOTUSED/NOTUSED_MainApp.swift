////
////  NOTUSED_MainApp.swift
////  Macintora
////
////  Created by Ilia Sazonov on 8/25/22.
////
//
//import Foundation
////
////  MacOraApp.swift
////  MacOra
////
////  Created by Ilia Sazonov on 10/4/21.
////
//
//import SwiftUI
//import os
//import UniformTypeIdentifiers
//import SwiftOracle
//
//extension Logger {
//    private static var subsystem = Bundle.main.bundleIdentifier!
//
//    /// Logs the view cycles like viewDidLoad.
//    var viewCycle: Logger { Logger(subsystem: Logger.subsystem, category: "viewcycle") }
//    var `default`: Logger { Logger(subsystem: Logger.subsystem, category: "default") }
//    var tnsReader: Logger { Logger(subsystem: Logger.subsystem, category: "tnsreader") }
//}
//
//let log = Logger().default
//
//
//@main
//struct MacOraApp: App {
////    @AppStorage("windowHeight") var windowHeight = "1200"
////    @AppStorage("windowWidth") var windowWidth = "1200"
//    @StateObject var appStateContainer = AppStateContainer()
//    @ObservedObject var appSettings = AppSettings.shared
//    @FocusedBinding(\.dbCache) var dbCache
//
//    var body: some Scene {
//        // Launch screen
////        WindowGroup {
////            WelcomeView()
////        }
////        .windowStyle(HiddenTitleBarWindowStyle())
////        .commands {
////            AppCommands()
////        }
//
//        DocumentGroup(newDocument: { MainDocumentVM() }) { config in
//                MainDocumentView(document: config.document)
//                    .preferredColorScheme(appSettings.currentTheme.colorScheme)
//                    .environmentObject(appSettings)
////                    .environmentObject(appStateContainer)
////                    .environmentObject(appStateContainer.tnsReader)
////                    .environment(\.managedObjectContext, config.document.dbCache.persistentController.container.viewContext)
//        }
//        .handlesExternalEvents(matching: ["file", "com.iliasazonov.macintora", "mcntr", "Macintora","test"])
////        .windowToolbarStyle(UnifiedWindowToolbarStyle(showsTitle: true))
//        .commands {
//            SidebarCommands()
//            ToolbarCommands()
//            MainDocumentMenuCommands()
//            TextEditingCommands()
//        }
//
//
//
////        WindowGroup("DB Browser") {
////            DBObjectsBrowser(cache: DBCache(connDetails: ConnectionDetails()))
////                .preferredColorScheme(appSettings.currentTheme.colorScheme)
////        }
////        .handlesExternalEvents(matching: ["dbBrowser"])
//
//        WindowGroup {
//            let cache = dbCache ?? DBCache(connDetails: ConnectionDetails())
//            DBCacheBrowserMainView()
//                .environment(\.managedObjectContext, cache.persistentController.container.viewContext)
//        }
//        .handlesExternalEvents(matching: ["dbBrowser"])
//        .commands {
//            SidebarCommands()
//            ToolbarCommands()
////            CommandGroup(after: .newItem) {
////                Button(action: {
////                    if let currentWindow = NSApp.keyWindow,
////                       let windowController = currentWindow.windowController {
////                        windowController.newWindowForTab(nil)
////                        if let newWindow = NSApp.keyWindow,
////                           currentWindow != newWindow {
////                            currentWindow.addTabbedWindow(newWindow, ordered: .above)
////                        }
////                    }
////                }) {
////                    Text("New Tab")
////                }
////                .keyboardShortcut("t", modifiers: [.command])
////
////                Button {
////                    var doc = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
////                } label: { Text("Copy Doc") }
////            }
//        }
//    }
//}
//
//struct MainDocumentMenuCommands: Commands {
//    @FocusedBinding(\.dbCache) var dbCache
//    var body: some Commands {
//        CommandMenu("Connection") {
//            let cache = dbCache ?? DBCache(connDetails: ConnectionDetails())
////            NavigationLink("DB Browser", destination: DBObjectsBrowser(cache: cache))
//            NavigationLink("DB Browser", destination: DBObjectsBrowser(cache: cache))
//                .environment(\.managedObjectContext, cache.persistentController.container.viewContext)
//                .disabled(dbCache == nil)
//                .presentedWindowStyle(TitleBarWindowStyle())
//                .keyboardShortcut("d", modifiers: .command)
//        }
//    }
//}
//
//
//struct DocumentFocusedKey: FocusedValueKey {
//    typealias Value = Binding<DBCache>
//}
//
//extension FocusedValues {
//    var dbCache: Binding<DBCache>? {
//        get {
//            self[DocumentFocusedKey.self]
//        }
//        set {
//            self[DocumentFocusedKey.self] = newValue
//        }
//    }
//}
//
//class AppSettings: ObservableObject {
//    static let shared = AppSettings()
//    @AppStorage("currentTheme") var currentTheme: Theme = .unspecified
////    @AppStorage("logLevel")  var logLevel: Logging.Logger.Level = .info
//
//    init() {
//
//    }
//
//    func setCurrentTheme() {
//        let currentTheme = AppSettings.shared.currentTheme
//        AppSettings.shared.currentTheme = currentTheme == .light ? .dark : .light
//    }
//}
//
//enum Theme: Int {
//    case light
//    case dark
//    case unspecified
//
//    var colorScheme: ColorScheme? {
//        switch self {
//        case .light:
//            return .light
//        case .dark:
//            return .dark
//        default: return nil
//        }
//    }
//}
//
//class AppStateContainer: ObservableObject {
//    public var tnsReader = TnsReader()
//}
//
//struct WindowAccessor: NSViewRepresentable {
//    @Binding var window: NSWindow?
//
//    func makeNSView(context: Context) -> NSView {
//        let view = NSView()
//        DispatchQueue.main.async {
//            self.window = view.window
//        }
//        return view
//    }
//
//    func updateNSView(_ nsView: NSView, context: Context) {}
//}
//
//private extension NSNotification.Name {
//    static let hideWelcomeWindow = NSNotification.Name(rawValue: "hide-welcome-window")
//}
//
//struct WelcomeView: View {
//    @State private var window: NSWindow?
////    @StateObject var model = AppViewModel()
//
//    var body: some View {
//        contents
//            .background(WindowAccessor(window: $window))
//            .onReceive(NotificationCenter.default.publisher(for: .hideWelcomeWindow), perform: { _ in
//                window?.close()
//            })
//    }
//
//    @ViewBuilder
//    private var contents: some View {
//        AppWelcomeView(buttonOpenDocumentTapped: openDocument)
//            .ignoresSafeArea()
//            .frame(width: 800, height: 460)
//    }
//}
//
//func openDocument() {
//    let dialog = NSOpenPanel()
//
//    dialog.title = "Select a MacOra document (has .macora extension)"
//    dialog.showsResizeIndicator = true
//    dialog.showsHiddenFiles = false
//    dialog.canChooseDirectories = false
//    dialog.canCreateDirectories = false
//    dialog.allowsMultipleSelection = false
//    dialog.canChooseDirectories = true
//    dialog.allowedContentTypes = [UTType.macora]
//
//    guard dialog.runModal() == NSApplication.ModalResponse.OK else {
//        return // User cancelled the action
//    }
//
//    if let selectedUrl = dialog.url {
//        NSWorkspace.shared.open(selectedUrl)
//    }
//}
//
//struct AppCommands: Commands {
//    var body: some Commands {
//        CommandGroup(before: .newItem) {
//            Button("Open", action: openDocument).keyboardShortcut("o")
//            Menu("Open Recent") {
//                ForEach(NSDocumentController.shared.recentDocumentURLs, id: \.self) { url in
//                    Button(action: { NSWorkspace.shared.open(url) }, label: {
//                        Text(url.lastPathComponent)
//                    })
//                }
//            }
//        }
//    }
//}
//
//
//struct AppView: View {
////    @StateObject var model = AppViewModel()
////    @StateObject var model = MainDocument()
//
//    var body: some View {
//        contents
//            .onOpenURL(perform: { (url: URL) in
//                let a = 1
//            } )
//    }
//
//    @ViewBuilder
//    private var contents: some View {
//        EmptyView()
//    }
//}
//
//
//public func toggleSidebar() {
//    NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
//}
