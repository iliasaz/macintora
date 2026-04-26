import Foundation
import Observation
import os

extension Logger {
    fileprivate static let connStore = Logger(subsystem: Logger.subsystem, category: "connstore")
}

/// App-wide list of saved Oracle connections.
///
/// One instance is created at app launch and injected into the SwiftUI
/// environment via ``ConnectionStoreKey``. Documents reference connections by
/// ``SavedConnection/id``; the editor and document picker read/write through
/// this store.
///
/// Persistence is a JSON file in `~/Library/Application Support/Macintora/
/// connections.json`, encoded as ``Envelope`` so future schema bumps are easy
/// to migrate.
@Observable @MainActor
final class ConnectionStore {
    /// On-disk format. Versioned so upgrades can detect old documents.
    private struct Envelope: Codable {
        var version: Int
        var connections: [SavedConnection]
    }

    /// Bumped only when the wire format changes in a non-additive way.
    static let currentVersion = 1

    private(set) var connections: [SavedConnection] = []

    /// File the store persists to. Visible for tests so they can point at a
    /// throwaway temp directory.
    let storeURL: URL

    /// Coalesces multiple mutations into one write.
    private var pendingSave: Task<Void, Never>?

    init(storeURL: URL? = nil) {
        let url = storeURL ?? Self.defaultStoreURL()
        self.storeURL = url
        load()
    }

    // MARK: - Reads

    func connection(id: UUID) -> SavedConnection? {
        connections.first { $0.id == id }
    }

    func connection(named name: String) -> SavedConnection? {
        let key = name.lowercased()
        return connections.first { $0.name.lowercased() == key }
    }

    // MARK: - Writes

    /// Inserts a new connection or replaces one with the same `id`. Updates
    /// `updatedAt` automatically.
    ///
    /// Updates replace in-place — we *don't* re-sort on every edit because
    /// the editor binds to the store live; sorting on each keystroke would
    /// make the row jitter under the user's cursor as they retyped a name.
    /// New entries do get sorted in.
    func upsert(_ connection: SavedConnection) {
        var copy = connection
        copy.updatedAt = .now
        if let idx = connections.firstIndex(where: { $0.id == copy.id }) {
            connections[idx] = copy
        } else {
            connections.append(copy)
            sortConnections()
        }
        scheduleSave()
    }

    /// Removes the connection and any Keychain secrets associated with it.
    func delete(id: UUID, keychain: KeychainService = KeychainService()) {
        guard connections.contains(where: { $0.id == id }) else { return }
        connections.removeAll { $0.id == id }
        keychain.deleteAll(for: id)
        scheduleSave()
    }

    /// Imports parsed `tnsnames.ora` entries into the store. Existing
    /// connections with the same name (case-insensitive) are updated in place
    /// — never duplicated. Returns the number of entries inserted plus
    /// updated.
    @discardableResult
    func importTnsEntries(_ entries: [TnsEntry]) -> Int {
        var changed = 0
        for entry in entries {
            if let existing = connection(named: entry.alias) {
                var updated = existing
                updated.host = entry.host
                updated.port = entry.port
                if let svc = entry.serviceName {
                    updated.service = .serviceName(svc)
                } else if let sid = entry.sid {
                    updated.service = .sid(sid)
                }
                upsert(updated)
            } else {
                upsert(SavedConnection(from: entry))
            }
            changed += 1
        }
        return changed
    }

    /// Convenience wrapper for the "Import tnsnames.ora…" UI action.
    @discardableResult
    func importFromTnsnames(at path: String) -> Int {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            Logger.connStore.error("could not read tnsnames.ora at \(path, privacy: .public)")
            return 0
        }
        return importTnsEntries(TnsParser.parse(contents))
    }

    // MARK: - Persistence

    private func sortConnections() {
        connections.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            connections = []
            return
        }
        do {
            let data = try Data(contentsOf: storeURL)
            let envelope = try Self.makeDecoder().decode(Envelope.self, from: data)
            connections = envelope.connections
            sortConnections()
        } catch {
            Logger.connStore.error("failed to decode connection store: \(error.localizedDescription, privacy: .public)")
            connections = []
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let snapshot = connections
        let url = storeURL
        pendingSave = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            Self.write(snapshot, to: url)
        }
    }

    /// Forces a synchronous write. Used by tests and when the app is about to
    /// terminate.
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        Self.write(connections, to: storeURL)
    }

    private static func write(_ connections: [SavedConnection], to url: URL) {
        let envelope = Envelope(version: ConnectionStore.currentVersion, connections: connections)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(envelope)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            Logger.connStore.error("failed to write connection store: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func defaultStoreURL() -> URL {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.documentsDirectory
        return support.appending(path: "Macintora", directoryHint: .isDirectory)
            .appending(path: "connections.json", directoryHint: .notDirectory)
    }
}

// JSONEncoder/Decoder defaults — we set iso8601 on encode but the decoder
// also has to opt in for round-tripping.
extension ConnectionStore {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
