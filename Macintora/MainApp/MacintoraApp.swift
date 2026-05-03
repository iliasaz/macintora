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
    private var pendingRestoreOpens = 0
    private var sessionObservers: [any NSObjectProtocol] = []
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

        // Validate the persisted window frame BEFORE any window opens. If
        // the saved frame lives on a now-disconnected display (or otherwise
        // doesn't meaningfully intersect any current screen) AppKit's
        // `setFrameAutosaveName` replays the bad frame, the window appears
        // off-screen, and SwiftUI's NavigationSplitView immediately drives
        // `_NSSplitViewItemViewWrapper.updateConstraints` past AppKit's
        // "more passes than views" safety net and crashes. The post-window
        // sanity check in `WindowLayoutPersister.ensureFrameIsOnScreen`
        // can't help — by the time `viewDidMoveToWindow` fires, the bad
        // layout has already aborted the app.
        WindowFrameSanitiser.sanitisePersistedFrames(
            autosaveNames: ["Macintora.MainDocument"],
            in: .standard,
            screens: NSScreen.screens)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When the app is launched as an XCTest host, skip session restore
        // and snapshot wiring entirely. Otherwise the test launch would
        // clobber the user's persisted session list with whatever the test
        // bundle happens to leave behind.
        if Self.isRunningInTestHost { return }

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

        restoreSessionIfNeeded()
    }

    private static var isRunningInTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
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
//    @FocusedValue(\.cacheConnectionDetails) var cacheConnectionDetails: ConnectionDetails?
    @FocusedValue(\.selectedObjectName) var selectedObjectName: String?
    @FocusedValue(\.mainConnection) var mainConnection
    @FocusedValue(\.editorQuickViewBox) var quickViewBox
    @FocusedValue(\.editorOpenInBrowserBox) var openInBrowserBox
    @Environment(\.openWindow) var openWindow

    @Environment(\.openSettings) private var openSettings

    @AppStorage(QuickViewHotkey.storageKey) private var quickViewHotkeyRaw: String = QuickViewHotkey.default.rawValue
    private var quickViewHotkey: QuickViewHotkey {
        QuickViewHotkey(rawValue: quickViewHotkeyRaw) ?? .default
    }

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

            Divider()

            // Disabled gating reads the box's identity (nil = no focused
            // editor capable of Quick View) rather than `box.trigger` —
            // see the long comment in `EditorQuickViewBox` for the
            // constraint-loop crash that observable trigger reads caused.
            Button("Quick View") {
                quickViewBox?.trigger?()
            }
            .disabled(quickViewBox == nil)
            .quickViewShortcut(quickViewHotkey)

            Button("Open in DB Browser") {
                openInBrowserBox?.trigger?()
            }
            .disabled(openInBrowserBox == nil)
            .keyboardShortcut("b", modifiers: [.command, .option])
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
