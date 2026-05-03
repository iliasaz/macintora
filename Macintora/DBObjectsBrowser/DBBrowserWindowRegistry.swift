//
//  DBBrowserWindowRegistry.swift
//  Macintora
//
//  Maintains a per-connection live index of open DB Browser windows so that
//  "Open in DB Browser" triggers can re-use an existing window instead of
//  booting a new CoreData stack each time.
//
//  Usage:
//   - `DBCacheMainView` registers itself via the `WindowObserver` background
//     view and deregisters on `onDisappear`.
//   - `openOrFocusDBBrowser(value:openWindow:)` checks the registry first;
//     if a matching window is found it focuses it and mutates its VM, otherwise
//     it calls `openWindow(value:)`.
//

import AppKit
import SwiftUI

// MARK: - Registry

/// Process-global, main-actor registry: TNS alias → (DBCacheVM, NSWindow).
@MainActor
final class DBBrowserWindowRegistry {
    static let shared = DBBrowserWindowRegistry()
    /// Internal so `@testable import Macintora` test suites can create
    /// isolated instances rather than sharing the process-global singleton.
    init() {}

    private struct Entry {
        let tns: String
        weak var vm: DBCacheVM?
        weak var window: NSWindow?
    }
    private var entries: [Entry] = []

    func register(vm: DBCacheVM, window: NSWindow) {
        // Idempotent: skip if this exact (vm, window) pair is already present.
        if entries.contains(where: { $0.vm === vm && $0.window === window }) { return }
        entries.removeAll { $0.vm === vm }
        entries.append(Entry(tns: vm.connDetails.tns, vm: vm, window: window))
        purge()
    }

    func deregister(vm: DBCacheVM) {
        entries.removeAll { $0.vm === vm }
    }

    /// Returns the first live (vm, window) pair whose TNS matches `tns`, or
    /// nil when no such window is currently open.
    func find(forTNS tns: String) -> (vm: DBCacheVM, window: NSWindow)? {
        purge()
        for entry in entries where entry.tns == tns {
            if let vm = entry.vm, let window = entry.window {
                return (vm, window)
            }
        }
        return nil
    }

    private func purge() {
        entries.removeAll { $0.vm == nil || $0.window == nil }
    }
}

// MARK: - Dedup open helper

/// Opens a DB Browser window pre-focused on the object described by `value`.
///
/// If a browser for the same connection (TNS) is already open, focuses that
/// window and mutates its VM so the user doesn't pay the CoreData bootstrap
/// cost of a fresh window. Falls back to `openWindow(value:)` when no match
/// is found.
@MainActor
func openOrFocusDBBrowser(value: DBCacheInputValue, openWindow: OpenWindowAction) {
    let tns = value.mainConnection.mainConnDetails.tns
    if let (vm, window) = DBBrowserWindowRegistry.shared.find(forTNS: tns) {
        // Update the existing VM's search criteria.
        if let name = value.selectedObjectName {
            vm.searchCriteria.searchText = name
        }
        if let owner = value.selectedOwner {
            vm.searchCriteria.ownerString = owner
        }
        vm.searchCriteria.selectedTypeFilter = value.selectedObjectType
        // Arm the auto-selection mechanism.
        vm.pendingSelectionName  = value.selectedObjectName
        vm.pendingSelectionOwner = value.selectedOwner
        vm.pendingSelectionType  = value.selectedObjectType
        vm.initialDetailTab      = value.initialDetailTab
        window.makeKeyAndOrderFront(nil)
    } else {
        openWindow(value: value)
    }
}

// MARK: - WindowObserver

/// A zero-size `NSViewRepresentable` that calls `onWindowResolved` once the
/// view has been placed in a window. Used by `DBCacheMainView` to register
/// itself with `DBBrowserWindowRegistry`.
struct WindowObserver: NSViewRepresentable {
    let onWindowResolved: (NSWindow) -> Void

    func makeNSView(context: Context) -> _WindowObserverView {
        _WindowObserverView(onWindowResolved: onWindowResolved)
    }

    func updateNSView(_ view: _WindowObserverView, context: Context) {
        if let window = view.window {
            onWindowResolved(window)
        }
    }
}

/// Internal `NSView` subclass that fires the callback when it moves into a
/// window hierarchy. Kept package-internal; callers use `WindowObserver`.
final class _WindowObserverView: NSView {
    private let onWindowResolved: (NSWindow) -> Void
    private var hasReported = false

    init(onWindowResolved: @escaping (NSWindow) -> Void) {
        self.onWindowResolved = onWindowResolved
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window, !hasReported {
            hasReported = true
            // Fire on the next run-loop turn so SwiftUI's layout pass has
            // completed and the window hierarchy is stable.
            MainActor.assumeIsolated {
                onWindowResolved(window)
            }
        }
    }
}
