//
//  Formatter.swift
//  DBObjectsBrowser
//
//  Created by Ilia on 6/4/22.
//

import Foundation
import SwiftUI
import os

extension Logger {
    var formatter: Logger { Logger(subsystem: Logger.subsystem, category: "formatter") }
}

class Formatter: ObservableObject {
    @Published var formattedSource: String = "... formatting, please wait ..."
    @AppStorage("formatterPath") private var formatterPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/Macintora/formatter"
    @AppStorage("shellPath") static private var shellPath = "/bin/zsh"
    
    func formatSource(name: String, text: String?) async -> String {
        guard var text = text else { return ""}
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let temporaryFilename = name + ".sql"
        let temporaryFileURL = temporaryDirectoryURL.appendingPathComponent(temporaryFilename)
        log.formatter.debug("temp file path: \(temporaryFileURL.path, privacy: .public)")
        
        defer { try? FileManager.default.removeItem(at: temporaryFileURL) }
        
        do {
            if (FileManager.default.createFile(atPath: temporaryFileURL.path, contents: nil, attributes: nil)) {
                log.formatter.debug("File created successfully.")
            } else {
                log.formatter.error("File not created.")
                return text
            }
            try text.write(to: temporaryFileURL, atomically: true, encoding: .utf8)
        } catch {
            log.formatter.error("File write failed: \(error)")
            return text
        }
        
        do {
            var output = await try Formatter.safeShell("\(formatterPath)/tvdformat \(temporaryFileURL.path) xml=\(formatterPath)/trivadis_advanced_format.xml arbori=\(formatterPath)/trivadis_custom_format.arbori")
            log.formatter.debug("tvdformat first pass output received: \(output, privacy: .public)")
            output = await try Formatter.safeShell("\(formatterPath)/tvdformat \(temporaryFileURL.path) xml=\(formatterPath)/trivadis_advanced_format.xml arbori=\(formatterPath)/trivadis_custom_format.arbori")
            log.formatter.debug("tvdformat final output received: \(output, privacy: .public)")
        }
        catch {
            log.formatter.error("tvdformat failed: \(error.localizedDescription, privacy: .public)") //handle or silence the error here
        }
        
        do {
            //            self.objectWillChange.send()
            text = try String.init(contentsOfFile: temporaryFileURL.path)
        }
        catch {
            log.formatter.error("file read failed: \(error.localizedDescription, privacy: .public)") //handle or silence the error here
        }
        
        return text
    }
    
    func formatSource(name: String, text: String?) {
        Task.detached(priority: .background) { [self] in
            let formattedText = await formatSource(name: name, text: text)
            
            await MainActor.run {
                self.formattedSource = formattedText
            }
        }
    }
    
    static func safeShell(_ command: String) async throws -> String {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.executableURL = URL(fileURLWithPath: shellPath)
        task.standardInput = nil
        
        try task.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)!
        
        return output
    }
}
