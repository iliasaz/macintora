import Foundation
import SwiftUI
import Combine
import os

extension Logger {
    var tnsReader: Logger { Logger(subsystem: Logger.subsystem, category: "tnsreader") }
}

/// Reads and parses `tnsnames.ora`, exposing the parsed entries and alias list to the UI.
@MainActor
final class TnsReader: nonisolated ObservableObject {
    @AppStorage("tnsnamesPath") var tnsnamesPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.oracle/tnsnames.ora"

    @Published private(set) var entries: [TnsEntry] = []
    @Published var suggestions: [String] = []

    var tnsAliases: [String] {
        entries.map(\.alias).sorted()
    }

    init() {
        log.tnsReader.debug("initializing: AppStorage tnsFilePath: \(self.tnsnamesPath, privacy: .public)")
        load()
    }

    func load() {
        do {
            let text = try String(contentsOfFile: tnsnamesPath, encoding: .utf8)
            entries = TnsParser.parse(text)
            log.tnsReader.debug("parsed \(self.entries.count, privacy: .public) TNS entries")
        } catch {
            log.error("Could not read tnsnames.ora file from path: \(self.tnsnamesPath, privacy: .public)")
            entries = []
        }
    }

    func entry(forAlias alias: String) -> TnsEntry? {
        let key = alias.lowercased()
        return entries.first { $0.alias.lowercased() == key }
    }

    func lookup(prefix: String) -> [String] {
        let lowercasedPrefix = prefix.lowercased()
        return tnsAliases.filter { $0.lowercased().hasPrefix(lowercasedPrefix) }
    }

    private func isSuggestion(in suggestions: [String], equalTo text: String) -> Bool {
        guard let suggestion = suggestions.first, suggestions.count == 1 else {
            return false
        }
        return suggestion.lowercased() == text.lowercased()
    }

    func autocomplete(_ text: String) {
        guard !text.isEmpty else {
            suggestions = []
            return
        }
        let newSuggestions = lookup(prefix: text)
        if isSuggestion(in: suggestions, equalTo: text) {
            suggestions = []
        } else {
            suggestions = newSuggestions
        }
    }
}
