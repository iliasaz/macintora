//
//  Utils.swift
//  MacOra
//
//  Created by Ilia on 11/3/21.
//

import Foundation
import Logging
import SwiftOracle
import CoreData
import SwiftUI

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
    func asyncMap<T>(
        _ transform: (Element) async throws -> T
    ) async rethrows -> [T] {
        var values = [T]()
        
        for element in self {
            try await values.append(transform(element))
        }
        
        return values
    }
}

extension Logger {
    public func error(_ error: DatabaseError) {
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


// support for Codable in @Appstorage
extension Array: RawRepresentable where Element: Codable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
            let result = try? JSONDecoder().decode([Element].self, from: data)
        else {
            return nil
        }
        self = result
    }

    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
            let result = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return result
    }
}

extension Dictionary: RawRepresentable where Key: Codable, Value: Codable {
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
