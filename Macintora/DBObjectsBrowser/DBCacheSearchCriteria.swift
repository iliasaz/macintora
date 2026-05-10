//
//  DBCacheSearchCriteria.swift
//
//  Created by Ilia on 1/17/22.
//

import Foundation
import CoreData
import os
import SwiftUI

/// Filter + search state for the DB Browser's object list. Plain stored
/// properties (no `@AppStorage`) so binding mutations through
/// `@Published`/`@Observable` reliably fire `objectWillChange`. UserDefaults
/// is read once in `init(for:)` and rewritten via `persist()` whenever the
/// hosting view model observes a change.
struct DBCacheSearchCriteria: Equatable {
    static func == (lhs: DBCacheSearchCriteria, rhs: DBCacheSearchCriteria) -> Bool {
        lhs.predicate == rhs.predicate
    }

    var searchText = ""
    var ownerString: String
    var prefixString: String
    var showTables: Bool
    var showViews: Bool
    var showIndexes: Bool
    var showPackages: Bool
    var showTypes: Bool
    var showTriggers: Bool
    var showProcedures: Bool
    var showFunctions: Bool

    /// When non-nil, overrides the `showXXX` type toggles and filters to
    /// only this Oracle object type (e.g. "TABLE"). Set by "Open in DB Browser"
    /// triggers so the list starts focused on the referenced object's type.
    /// Cleared when the user resets the type filter from `QuickFilterView`.
    var selectedTypeFilter: String? = nil

    private let tns: String

    var ownerInclusionList: [String] {
        ownerString.uppercased().components(separatedBy: ",").compactMap { let trimmed = $0.trimmingCharacters(in: .whitespaces); return trimmed.isEmpty ? nil : trimmed }
    }

    var namePrefixInclusionList: [String] {
        prefixString.components(separatedBy: ",").compactMap { let trimmed = $0.uppercased().trimmingCharacters(in: .whitespaces); return trimmed.isEmpty ? nil : trimmed }
    }

    init(for tns: String) {
        self.tns = tns
        let d = UserDefaults.standard
        self.showTables = d.object(forKey: Keys.showTables) as? Bool ?? true
        self.showViews = d.object(forKey: Keys.showViews) as? Bool ?? true
        self.showIndexes = d.object(forKey: Keys.showIndexes) as? Bool ?? true
        self.showPackages = d.object(forKey: Keys.showPackages) as? Bool ?? true
        self.showTypes = d.object(forKey: Keys.showTypes) as? Bool ?? true
        self.showTriggers = d.object(forKey: Keys.showTriggers) as? Bool ?? true
        self.showProcedures = d.object(forKey: Keys.showProcedures) as? Bool ?? true
        self.showFunctions = d.object(forKey: Keys.showFunctions) as? Bool ?? true
        let ownerList = d.dictionary(forKey: Keys.ownerList) as? [String: String] ?? [:]
        let prefixList = d.dictionary(forKey: Keys.prefixList) as? [String: String] ?? [:]
        self.ownerString = ownerList[tns] ?? ""
        self.prefixString = prefixList[tns] ?? ""
    }

    func persist() {
        let d = UserDefaults.standard
        d.set(showTables, forKey: Keys.showTables)
        d.set(showViews, forKey: Keys.showViews)
        d.set(showIndexes, forKey: Keys.showIndexes)
        d.set(showPackages, forKey: Keys.showPackages)
        d.set(showTypes, forKey: Keys.showTypes)
        d.set(showTriggers, forKey: Keys.showTriggers)
        d.set(showProcedures, forKey: Keys.showProcedures)
        d.set(showFunctions, forKey: Keys.showFunctions)
        var ownerList = d.dictionary(forKey: Keys.ownerList) as? [String: String] ?? [:]
        ownerList[tns] = ownerString
        d.set(ownerList, forKey: Keys.ownerList)
        var prefixList = d.dictionary(forKey: Keys.prefixList) as? [String: String] ?? [:]
        prefixList[tns] = prefixString
        d.set(prefixList, forKey: Keys.prefixList)
    }

    var predicate: NSPredicate {
        var predicates = [NSPredicate]()

        if let forced = selectedTypeFilter {
            predicates.append(NSPredicate(format: "type_ = %@", forced))
        } else {
            var typeInclusionList = [String]()
            if showTables { typeInclusionList.append("TABLE") }
            if showTypes { typeInclusionList.append("TYPE") }
            if showProcedures { typeInclusionList.append("PROCEDURE") }
            if showFunctions { typeInclusionList.append("FUNCTION") }
            if showViews { typeInclusionList.append("VIEW") }
            if showIndexes { typeInclusionList.append("INDEX") }
            if showPackages { typeInclusionList.append("PACKAGE") }
            if showTriggers { typeInclusionList.append("TRIGGER") }
            if !typeInclusionList.isEmpty {
                predicates.append(NSPredicate(format: "type_ IN %@", typeInclusionList))
            }
        }

        if !ownerInclusionList.isEmpty {
            predicates.append(NSPredicate(format: "owner_ IN %@", ownerInclusionList))
        }

        if !searchText.isEmpty {
            predicates.append(NSPredicate.init(format: "name_ CONTAINS[c] %@", searchText))
        }
        if !namePrefixInclusionList.isEmpty {
            predicates.append(NSCompoundPredicate.init(type: .or, subpredicates: namePrefixInclusionList.map { NSPredicate.init(format: "name_ BEGINSWITH[c] %@", $0) } ))
        }

        log.cache.debug("criteria: \(predicates, privacy: .public)")
        return NSCompoundPredicate.init(type: .and, subpredicates: predicates)
    }

    private enum Keys {
        static let showTables = "showTables"
        static let showViews = "showViews"
        static let showIndexes = "showIndexes"
        static let showPackages = "showPackages"
        static let showTypes = "showTypes"
        static let showTriggers = "showTriggers"
        static let showProcedures = "showProcedures"
        static let showFunctions = "showFunctions"
        static let ownerList = "ownerList"
        static let prefixList = "prefixList"
    }
}
