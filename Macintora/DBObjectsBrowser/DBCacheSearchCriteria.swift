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

    /// When true, the per-type `showXXX` toggles are ignored entirely so the
    /// list isn't constrained by object type. Set when the DB Browser is
    /// opened pre-focused on an object whose type isn't known up front (a bare
    /// `owner.name` reference): the user asked for that object, so the type
    /// toggles must not hide it. Cleared as soon as the user touches a type
    /// toggle in `QuickFilterView`. Session-only — never persisted.
    var ignoreTypeFilter: Bool = false

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
        } else if !ignoreTypeFilter {
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

/// Canned starting points for the quick-filter popover. The "Custom" preset is
/// implicit — it's whatever the user's toggles are *not* matching, so it isn't
/// applied; it just labels the current state.
enum DBCacheFilterPreset: String, CaseIterable, Identifiable {
    case `default`
    case tablesOnly
    case codeOnly
    case schemaReview

    var id: Self { self }

    var label: String {
        switch self {
        case .default:      "Default"
        case .tablesOnly:   "Tables only"
        case .codeOnly:     "Code only"
        case .schemaReview: "Schema review"
        }
    }
}

extension DBCacheSearchCriteria {
    /// Applies a preset to the per-type toggles. Doesn't touch owner / prefix /
    /// search text — those are user-curated and should persist across preset
    /// flips. Clears the transient single-type override so the toggles take
    /// effect immediately.
    mutating func applyPreset(_ preset: DBCacheFilterPreset) {
        ignoreTypeFilter = false
        selectedTypeFilter = nil
        switch preset {
        case .default:
            showTables = true; showViews = true; showIndexes = true
            showPackages = true; showProcedures = true; showFunctions = true
            showTriggers = true; showTypes = true
        case .tablesOnly:
            showTables = true; showViews = false; showIndexes = false
            showPackages = false; showProcedures = false; showFunctions = false
            showTriggers = false; showTypes = false
        case .codeOnly:
            showTables = false; showViews = false; showIndexes = false
            showPackages = true; showProcedures = true; showFunctions = true
            showTriggers = true; showTypes = true
        case .schemaReview:
            // Everything except indexes — most reviewers don't need to scroll
            // past dozens of secondary indexes.
            showTables = true; showViews = true; showIndexes = false
            showPackages = true; showProcedures = true; showFunctions = true
            showTriggers = true; showTypes = true
        }
    }

    /// Best-fit preset for the current toggle state, or nil if it doesn't
    /// match any canned preset (i.e. the user has a Custom configuration).
    var matchingPreset: DBCacheFilterPreset? {
        for preset in DBCacheFilterPreset.allCases {
            var probe = self
            probe.applyPreset(preset)
            if probe.showTables == showTables, probe.showViews == showViews,
               probe.showIndexes == showIndexes, probe.showPackages == showPackages,
               probe.showProcedures == showProcedures, probe.showFunctions == showFunctions,
               probe.showTriggers == showTriggers, probe.showTypes == showTypes,
               selectedTypeFilter == nil, !ignoreTypeFilter {
                return preset
            }
        }
        return nil
    }
}
