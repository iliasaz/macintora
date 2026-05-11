//
//  DBBrowserPinnedStore.swift
//  Macintora
//
//  Per-TNS pinned-object persistence. Stores a list of "owner|name|type"
//  strings in UserDefaults keyed by TNS — small enough not to bother with
//  Core Data, and the on-disk format survives across cache rebuilds.
//

import Foundation
import Combine

/// Stable identifier for a pinned object across cache rebuilds. Equality is
/// on the (owner, name, type) triple; the underlying Core Data row may be
/// dropped & re-created during a refresh.
struct DBPinnedKey: Hashable, Codable {
    let owner: String
    let name: String
    let type: String

    var encoded: String { "\(owner)|\(name)|\(type)" }

    init(owner: String, name: String, type: String) {
        self.owner = owner
        self.name = name
        self.type = type
    }

    init?(encoded: String) {
        let parts = encoded.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return nil }
        self.owner = parts[0]
        self.name  = parts[1]
        self.type  = parts[2]
    }

    init(_ object: DBCacheObject) {
        self.init(owner: object.owner, name: object.name, type: object.type)
    }
}

/// Observable store. Mutations publish via `objectWillChange` so SwiftUI views
/// holding it as `@ObservedObject`/`@StateObject` redraw immediately.
final class DBBrowserPinnedStore: ObservableObject {
    private let tns: String
    private let defaults: UserDefaults
    private static let storeKey = "dbBrowserPinned"

    @Published private(set) var keys: [DBPinnedKey]

    init(tns: String, defaults: UserDefaults = .standard) {
        self.tns = tns
        self.defaults = defaults
        self.keys = Self.load(tns: tns, defaults: defaults)
    }

    func isPinned(_ key: DBPinnedKey) -> Bool {
        keys.contains(key)
    }

    func toggle(_ key: DBPinnedKey) {
        if let idx = keys.firstIndex(of: key) {
            keys.remove(at: idx)
        } else {
            keys.append(key)
        }
        persist()
    }

    func pin(_ key: DBPinnedKey) {
        guard !keys.contains(key) else { return }
        keys.append(key)
        persist()
    }

    func unpin(_ key: DBPinnedKey) {
        guard let idx = keys.firstIndex(of: key) else { return }
        keys.remove(at: idx)
        persist()
    }

    // MARK: - Storage

    private static func load(tns: String, defaults: UserDefaults) -> [DBPinnedKey] {
        let dict = defaults.dictionary(forKey: storeKey) as? [String: [String]] ?? [:]
        return (dict[tns] ?? []).compactMap(DBPinnedKey.init(encoded:))
    }

    private func persist() {
        var dict = defaults.dictionary(forKey: Self.storeKey) as? [String: [String]] ?? [:]
        dict[tns] = keys.map(\.encoded)
        defaults.set(dict, forKey: Self.storeKey)
    }
}
