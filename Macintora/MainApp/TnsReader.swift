//
//  TnsReader.swift
//  MacOra
//
//  Created by Ilia on 11/18/21.
//

import Foundation
import SwiftUI
import os

extension Logger {
    var tnsReader: Logger { Logger(subsystem: Logger.subsystem, category: "tnsreader") }
}

public class TnsReader: ObservableObject {
    @AppStorage("tnsnamesPath") private var tnsnamesPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/instantclient_19_8/network/admin/tnsnames.ora"
    @Published public var tnsAliases = [String]()
    @Published var suggestions: [String] = []
    
    init() {
        log.tnsReader.debug("initializing: AppStorage tnsFilePath: \(self.tnsnamesPath, privacy: .public)")
//        log.tnsReader.debug("TNS_ADMIN env var: \(ProcessInfo.processInfo.environment["TNS_ADMIN"] ?? "", privacy: .public)")
//        log.tnsReader.debug("ORACLE_HOME env var: \(ProcessInfo.processInfo.environment["ORACLE_HOME"] ?? "", privacy: .public)")
//        let fileManager = FileManager.default
        
//        if tnsFilePath.isEmpty || !(fileManager.fileExists(atPath: self.tnsFilePath)) { // didn't save it yet, or doesn't exists, check env variables
//            if let tnsAdminEnv = ProcessInfo.processInfo.environment["TNS_ADMIN"] {
//                tnsFilePath = tnsAdminEnv + "/tnsnames.ora"
//            } else if let oraHomeEnv = ProcessInfo.processInfo.environment["ORACLE_HOME"] {
//                tnsFilePath = oraHomeEnv + "/network/admin/tnsnames.ora"
//            } else { // guess
//                tnsFilePath = FileManager.default.homeDirectoryForCurrentUser.path + "/instantclient_19_8/network/admin/tnsnames.ora"
//            }
//        }
        log.tnsReader.debug("actual tnsFilePath: \(self.tnsnamesPath, privacy: .public)")
        load()
    }
    
    public func load() {
        do {
            let text = try String(contentsOfFile: tnsnamesPath, encoding: .utf8)
            tnsAliases = text.components(separatedBy: "\n").compactMap { $0.components(separatedBy: "=").first?.lowercased().trimmingCharacters(in: [" ","\r","\t","\n"]) }
                .filter { !$0.isEmpty }
                .sorted()
            log.tnsReader.debug("tns aliases: \(self.tnsAliases)")
        } catch {
            log.error("Could not read tnsnames.ora file from path: \(self.tnsnamesPath, privacy: .public)")
        }
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
//        log.debug("suggestions: \(newSuggestions)")
        if isSuggestion(in: suggestions, equalTo: text) {
            // Do not offer only one suggestion same as the input
            suggestions = []
        } else {
            suggestions = newSuggestions
        }
    }
}


