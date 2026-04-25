//
//  Utils.swift
//  MacOra
//
//  Created by Ilia on 11/3/21.
//

import Foundation
import os
import CoreData
import SwiftUI
import AppKit
import UniformTypeIdentifiers


struct Constants {
    static let maxColumnWidth: CGFloat = 1500.0
    static let minColumnWidth: CGFloat = 50.0
    static let nullValue: String = "(null)"
    static let minConnections = 3
    static let maxConnections = 5
    static let connectionTimeout = 180
    static let docViewMinHeight: CGFloat = 100.0
    static let initialDocViewHeight: CGFloat = 200.0
    static let queryResultViewMinHeight: CGFloat = 100.0
    static let defaultDBName: String = "preview"
    static let minDate: Date = Date(timeIntervalSince1970: 0)
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

extension Sequence where Element: Hashable {
    func unique() -> [Element] {
        var set = Set<Element>()
        return filter {set.insert($0).inserted}
    }
}

extension Sequence where Iterator.Element == NSAttributedString {
    func joined(with separator: NSAttributedString) -> NSAttributedString {
        return self.reduce(NSMutableAttributedString()) {
            (r, e) in
            if r.length > 0 {
                r.append(separator)
            }
            r.append(e)
            return r
        }
    }
    
    func joined(with separator: String = "") -> NSAttributedString {
        return self.joined(with: NSAttributedString(string: separator))
    }
}

extension Sequence {
    /// `@concurrent` keeps the awaited transforms off the caller's actor under
    /// Swift 6.2's `NonisolatedNonsendingByDefault` rule — without it the
    /// closure would inherit the caller's actor (typically MainActor) and
    /// serialise every iteration on the UI thread.
    @concurrent
    func asyncMap<T>(
        _ transform: @concurrent (Element) async throws -> T
    ) async rethrows -> [T] {
        var values = [T]()
        
        for element in self {
            try await values.append(transform(element))
        }
        
        return values
    }
}

extension Logger {
    func error(_ error: AppDBError) {
        self.error("\(error.description)")
    }
}

extension String {
    func firstIndex(of subString: String, after index: String.Index) -> String.Index? {
        return self[index...].range(of: subString)?.lowerBound
    }
    
    func firstIndex(of subString: String, before index: String.Index) -> String.Index? {
        return self[..<index].range(of: subString, options: String.CompareOptions.backwards)?.lowerBound
    }
}

extension View {
    func hidden(_ shouldHide: Bool) -> some View {
        opacity(shouldHide ? 0 : 1)
    }
}

func ~=<T: Equatable>(pattern: [T], value: T) -> Bool {
    return pattern.contains(value)
}


// Support `[Key: Value]` (Key/Value: Codable) in `@AppStorage`. `@retroactive`
// acknowledges that this is a retroactive conformance on a stdlib type — if
// Apple later ships their own `Dictionary: RawRepresentable` we'd lose this
// definition, but that conflict is loud at build time, not silent. The
// (unused) `Array: RawRepresentable` companion was removed.
extension Dictionary: @retroactive RawRepresentable where Key: Codable, Value: Codable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode([Key: Value].self, from: data)
        else {
            return nil
        }
        self = result
    }

    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
            let result = String(data: data, encoding: .utf8)
        else {
            return "[:]"
        }
        return result
    }
}

extension Animation {
    func `repeat`(while expression: Bool, autoreverses: Bool = true) -> Animation {
        if expression {
            return self.repeatForever(autoreverses: autoreverses)
        } else {
            return self
        }
    }
}

@MainActor
public func showSavePanel(defaultName: String, defaultExtensions: [UTType] = []) -> URL? {
    let savePanel = NSSavePanel()
    if !defaultExtensions.isEmpty {
        savePanel.allowedContentTypes = defaultExtensions
        savePanel.allowsOtherFileTypes = true
    }
    savePanel.canCreateDirectories = true
    savePanel.isExtensionHidden = false
    savePanel.title = "Save"
    savePanel.message = "Choose a folder and a name to store your value."
    savePanel.nameFieldLabel = "File name:"
    savePanel.nameFieldStringValue = defaultName
    savePanel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    
    // display the dialog
    let response = savePanel.runModal()
    return response == .OK ? savePanel.url : nil
}

extension String  {
    func conformsTo(pattern: String) -> Bool {
        let pattern = NSPredicate(format:"SELF MATCHES %@", pattern)
        return pattern.evaluate(with: self)
    }
}

extension NSColor {
    class func fromHex(hex: Int, alpha: Float) -> NSColor {
        let red = CGFloat((hex & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((hex & 0xFF00) >> 8) / 255.0
        let blue = CGFloat((hex & 0xFF)) / 255.0
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1.0)
    }
    
    class func fromHexString(hex: String, alpha: Float) -> NSColor? {
        // Handle two types of literals: 0x and # prefixed
        var cleanedString = ""
        if hex.hasPrefix("0x") {
            cleanedString = String(hex[hex.index(hex.startIndex, offsetBy: 2)...])
        } else if hex.hasPrefix("#") {
            cleanedString = String(hex[hex.index(hex.startIndex, offsetBy: 1)...])
        }
        // Ensure it only contains valid hex characters 0
        let validHexPattern = "[a-fA-F0-9]+"
        if cleanedString.conformsTo(pattern: validHexPattern) {
            // Modern replacement for the deprecated `Scanner.scanHexInt32(_:)`:
            // parse the hex string straight into a UInt64. The 24-bit colour
            // value still fits comfortably.
            guard let theInt = UInt64(cleanedString, radix: 16) else { return nil }
            let red = CGFloat((theInt & 0xFF0000) >> 16) / 255.0
            let green = CGFloat((theInt & 0xFF00) >> 8) / 255.0
            let blue = CGFloat((theInt & 0xFF)) / 255.0
            return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1.0)
    
        } else {
            return nil
        }
    }
}
