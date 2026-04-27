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
