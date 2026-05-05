//
//  MacOraApp.swift
//  MacOra
//
//  Created by Ilia Sazonov on 10/4/21.
//

import SwiftUI
import Combine
import os
import Synchronization
import UniformTypeIdentifiers
import OracleNIO

extension Logger {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.iliasazonov.macintora"

    /// Logs the view cycles like viewDidLoad.
    var viewCycle: Logger { Logger(subsystem: Logger.subsystem, category: "viewcycle") }
    var `default`: Logger { Logger(subsystem: Logger.subsystem, category: "default") }
}

let log = Logger().default

/// Owns launch-time document handling. Two responsibilities:
///
/// 1. Force an Untitled document on launch instead of the `NSOpenPanel` that
///    macOS's default DocumentGroup flow would otherwise present. Files passed
///    via Finder/CLI still open via the standard `application(_:open:)` path.
///
/// 2. Restore the previous session's saved documents at launch. URLs are
///    snapshotted on every window key/close (and again on clean ⌘Q) to a
///    UserDefaults list, then reopened from `applicationDidFinishLaunching` —
///    SwiftUI's DocumentGroup auto-creates an Untitled doc before
///    `applicationShouldOpenUntitledFile` would fire, so that classic hook
///    can't be used here. Restored docs do NOT auto-connect even if their
///    `MainModel.autoConnect == true`; the suppression flag on
///    `MainDocumentVM` is held until every restore-time `init(documentData:)`
///    has finished.
@MainActor
final class MacintoraAppDelegate: NSObject {
    private let sessionRestorer = SessionRestorer()
    private var launchGuard = LaunchGuard()
    private var pendingRestoreOpens = 0
    private var sessionObservers: [any NSObjectProtocol] = []
    private var transformationKeyMonitor: Any?
    /// Snapshots are no-ops while a restore is in progress; otherwise the
    /// auto-created Untitled doc that SwiftUI shows during launch wipes the
    /// persisted URL list before restore opens have populated documents.
    private var restoreInProgress = false
}

extension MacintoraAppDelegate: nonisolated NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders: on some macOS versions the "Show Open panel at
        // startup" behaviour is driven by this global default rather than the
        // delegate method below. Registering a default of NO doesn't override
        // a user's explicit preference — it just changes the *default*.
        UserDefaults.standard.register(defaults: [
            "NSShowAppCentricOpenPanelInsteadOfUntitledFile": false
        ])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Wire ⌘U / ⌘L to NSText's `uppercaseWord:` / `lowercaseWord:` via
        // a local event monitor. Setting `keyEquivalent` on AppKit's
        // auto-injected Edit > Transformations menu items doesn't reliably
        // route keyboard presses through to the responder chain (the
        // binding is visible in the menu but key-equivalent dispatch
        // silently no-ops in this app — likely SwiftUI's command
        // reconciliation interferes). The monitor sees the keyDown
        // before NSWindow.sendEvent and dispatches via NSApp.sendAction.
        installTransformationKeyMonitor()

        // When the app is launched as an XCTest host, skip session restore
        // and snapshot wiring entirely. Otherwise the test launch would
        // clobber the user's persisted session list with whatever the test
        // bundle happens to leave behind.
        if Self.isRunningInTestHost { return }

        // Mark this launch as in-flight before doing anything that could
        // crash. Captures the *previous* run's clean-exit signal so we can
        // decide whether to attempt session restore.
        let previousRunWasClean = launchGuard.beginLaunch()

        // `OperationQueue.main` runs callbacks on the main thread, but the
        // closure type isn't compile-time MainActor — wrap each body with
        // `MainActor.assumeIsolated`.
        let center = NotificationCenter.default
        let main = OperationQueue.main
        sessionObservers.append(
            center.addObserver(forName: NSWindow.didBecomeMainNotification, object: nil, queue: main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleSessionSnapshot() }
            }
        )
        sessionObservers.append(
            center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleSessionSnapshot() }
            }
        )

        if previousRunWasClean {
            restoreSessionIfNeeded()
        } else {
            log.notice("Skipping session restore — previous launch did not exit cleanly. The session list is preserved and will be reopened normally on the next clean launch.")
        }

        // Clear the launch flag after a short grace period so a force-quit
        // (or any other non-`applicationWillTerminate` exit) during normal
        // use doesn't suppress restore on the *next* launch. The window
        // here just needs to be long enough for a startup crash to happen
        // before we decide the run is healthy.
        Task { @MainActor [launchGuard] in
            try? await Task.sleep(for: .seconds(5))
            launchGuard.markCleanShutdown()
        }
    }

    private static var isRunningInTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Catch ⌘U / ⌘L pre-window-dispatch and route them to NSText's
    /// `uppercaseWord:` / `lowercaseWord:` via the responder chain.
    /// `NSApp.sendAction(_:to:from:)` returns `true` only when a responder
    /// in the chain handled the action; in that case we consume the event.
    /// Otherwise we let it propagate (e.g. the user pressed ⌘U while a
    /// non-text responder was focused — original behavior preserved).
    private func installTransformationKeyMonitor() {
        guard transformationKeyMonitor == nil else { return }
        transformationKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods == .command else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "u":
                if NSApp.sendAction(#selector(NSText.uppercaseWord(_:)), to: nil, from: nil) {
                    return nil
                }
            case "l":
                if NSApp.sendAction(#selector(NSText.lowercaseWord(_:)), to: nil, from: nil) {
                    return nil
                }
            default:
                break
            }
            return event
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // SwiftUI's DocumentGroup typically auto-creates the Untitled doc
        // before this hook fires on cold launch, so its return value is
        // effectively unused. Keep `true` for the rare cases where it does.
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Final save on clean ⌘Q. Force through even if a restore was still
        // in flight so we capture the user's actual final state.
        if Self.isRunningInTestHost { return }
        restoreInProgress = false
        snapshotSession()
        launchGuard.markCleanShutdown()
    }
}

extension MacintoraAppDelegate {
    private func restoreSessionIfNeeded() {
        let urls = sessionRestorer.restorableURLs()
        guard !urls.isEmpty else { return }

        // Don't re-open files that are already open (e.g., user double-clicked
        // a .macintora in Finder to launch — that file is already a doc).
        let alreadyOpen = Set(NSDocumentController.shared.documents
            .compactMap(\.fileURL)
            .map(\.standardizedFileURL))
        let toOpen = urls.filter { !alreadyOpen.contains($0.standardizedFileURL) }
        guard !toOpen.isEmpty else { return }

        restoreInProgress = true
        pendingRestoreOpens = toOpen.count
        MainDocumentVM.suppressAutoConnectOnLoad.withLock { $0 = true }

        let controller = NSDocumentController.shared
        for url in toOpen {
            controller.openDocument(withContentsOf: url, display: true) { [weak self] _, _, error in
                MainActor.assumeIsolated {
                    if let error {
                        log.error("session restore failed for \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    }
                    self?.restoreOpenDidFinish()
                }
            }
        }
    }

    private func restoreOpenDidFinish() {
        pendingRestoreOpens -= 1
        guard pendingRestoreOpens <= 0 else { return }

        pendingRestoreOpens = 0
        MainDocumentVM.suppressAutoConnectOnLoad.withLock { $0 = false }

        // Close the auto-created Untitled now that restored docs are visible.
        // Only close docs with no fileURL AND no edits — never destroy work.
        let pristine = NSDocumentController.shared.documents.filter {
            $0.fileURL == nil && !$0.isDocumentEdited
        }
        for doc in pristine { doc.close() }

        restoreInProgress = false
    }

    /// Defer one main-actor hop so the documents collection has settled
    /// (`willClose` fires before NSDocumentController has dropped the closing
    /// doc; `didBecomeMain` may fire mid-open before `addDocument`).
    private func scheduleSessionSnapshot() {
        Task { @MainActor in
            self.snapshotSession()
        }
    }

    private func snapshotSession() {
        guard !restoreInProgress else { return }
        let urls = NSDocumentController.shared.documents.compactMap(\.fileURL)
        sessionRestorer.saveSession(urls: urls)
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
                .task(id: config.fileURL) {
                    config.document.fileURL = config.fileURL
                }
        }
        .defaultSize(width: 1100, height: 700)
        // Bind the NSWindow's minimum size to the content's `.frame(minWidth:minHeight:)`
        // above. Without this, SwiftUI's default `automatic` resizability lets
        // the user drag the window past the content minimum — at which point
        // NavigationSplitView's column constraints can't be satisfied and the
        // constraint engine thrashes ("more Update Constraints in Window
        // passes than there are views in the window") and aborts.
        .windowResizability(.contentMinSize)
        .handlesExternalEvents(matching: ["file"])
        .commands {
            TextEditingCommands()
            SidebarCommands()
            ToolbarCommands()
            MainDocumentMenuCommands()
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
            let cache = DBCacheVM(
                connDetails: v.mainConnection.mainConnDetails,
                selectedOwner: v.selectedOwner,
                selectedObjectName: v.selectedObjectName,
                selectedObjectType: v.selectedObjectType,
                initialDetailTab: v.initialDetailTab)
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
    @FocusedValue(\.editorQuickViewBox) var quickViewBox
    @FocusedValue(\.editorOpenInBrowserBox) var openInBrowserBox
    @FocusedValue(\.sessionBrowserBox) var sessionBrowserBox
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandMenu("Database") {
            Button("Manage Connections…") {
                openSettings()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Divider()

            // The trigger handles both "cursor on token" (opens scrolled to
            // the object) and "cursor not on token" (opens a plain browser
            // for the editor's connection). The connection comes from the
            // closure captured in `wireOpenInBrowserHandler`, so the menu
            // doesn't need a `mainConnection` of its own.
            Button("Database Browser") {
                openInBrowserBox?.trigger?()
            }
            .disabled(openInBrowserBox == nil)
            .keyboardShortcut("i", modifiers: [.command, .shift])

            // Same pattern as Database Browser: the trigger captures the
            // document + `OpenWindowAction` at install time, so this menu
            // doesn't need to know the focused connection.
            Button("Session Browser") {
                sessionBrowserBox?.trigger?()
            }
            .disabled(sessionBrowserBox == nil)
            .keyboardShortcut("s", modifiers: [.command, .control, .shift])

            Divider()

            // Disabled gating reads the box's identity (nil = no focused
            // editor capable of Quick View) rather than `box.trigger` —
            // see the long comment in `EditorQuickViewBox` for the
            // constraint-loop crash that observable trigger reads caused.
            Button("Quick View") {
                quickViewBox?.trigger?()
            }
            .disabled(quickViewBox == nil)
            .keyboardShortcut("i", modifiers: [.command])
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
