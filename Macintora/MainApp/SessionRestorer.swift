import Foundation

/// Persists the URLs of the documents that were open at the last quit so we
/// can reopen them automatically on the next launch.
///
/// Untitled (never-saved) documents have no `fileURL` and are filtered out by
/// the caller before they reach `saveSession(urls:)`. URLs are stored as
/// `absoluteString`s in `UserDefaults`. Plain strings are sufficient because
/// the app is not sandboxed (`Macintora.entitlements` has no `app-sandbox`
/// key); if sandboxing is added later, swap the storage shape for
/// security-scoped bookmark `Data` here without touching the AppDelegate.
struct SessionRestorer {
    static let defaultsKey = "Macintora.SessionDocumentURLs"

    var defaults: UserDefaults = .standard
    var fileManager: FileManager = .default

    /// URLs that were open at last quit AND still exist on disk. Files that
    /// have since been moved or deleted are silently dropped.
    func restorableURLs() -> [URL] {
        let stored = defaults.array(forKey: Self.defaultsKey) as? [String] ?? []
        return stored.compactMap { URL(string: $0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    /// Persist the supplied URLs as the next session's restore list.
    /// Pass an empty array to clear the slot.
    func saveSession(urls: [URL]) {
        var seen = Set<String>()
        let strings = urls
            .map { $0.standardizedFileURL.absoluteString }
            .filter { seen.insert($0).inserted }
        defaults.set(strings, forKey: Self.defaultsKey)
    }
}

/// Crash-loop guard for session restore. The app persists open document
/// URLs in `SessionRestorer` and replays them at launch — if a restored
/// document crashes during open (a malformed worksheet, a layout bug
/// triggered by a monitor change, etc.) the app re-crashes on every launch
/// and the user has no escape hatch short of editing UserDefaults or
/// renaming the file on disk.
///
/// `LaunchGuard.beginLaunch(defaults:)` flips a "launch in progress" flag
/// in defaults. The flag is cleared on clean termination
/// (`markCleanShutdown`) and after a short post-launch grace window
/// (`scheduleClearAfterGracePeriod`). If the next launch sees the flag
/// already set, the previous run did not exit cleanly — assume a crash and
/// skip session restore exactly once.
///
/// This is intentionally narrower than full `NSWindow` state preservation:
/// it provides the most valuable property of that mechanism (suppress
/// replay after an unclean exit) without the larger encoder/coordinator
/// commitment.
struct LaunchGuard {
    static let defaultsKey = "Macintora.SessionLaunchInProgress"

    var defaults: UserDefaults = .standard

    /// Records that a launch has started and reports whether the previous
    /// run exited cleanly. Always sets the flag to `true` so a crash later
    /// in the launch sequence leaves the flag dirty for the next run.
    ///
    /// - Returns: `true` when the previous run terminated cleanly and
    ///   session restore should proceed; `false` when the previous run
    ///   did not clear the flag — treat as a crash and skip restore.
    mutating func beginLaunch() -> Bool {
        let previousRunCrashed = defaults.bool(forKey: Self.defaultsKey)
        defaults.set(true, forKey: Self.defaultsKey)
        return !previousRunCrashed
    }

    /// Clears the launch flag. Called from `applicationWillTerminate`, and
    /// also after a post-launch grace period so a clean run that doesn't
    /// terminate via `applicationWillTerminate` (e.g. force-quit during
    /// idle use) doesn't poison the next launch.
    func markCleanShutdown() {
        defaults.set(false, forKey: Self.defaultsKey)
    }
}
