//
//  DBCacheSearchCriteriaTests.swift
//  MacintoraTests
//
//  Covers the DB Browser filter state (issue #25, Items 1, 16, 17):
//  - mutating a type toggle / owner / prefix / search text changes the
//    derived `predicate` (and therefore `Equatable`), which is what makes
//    `onChange(of: cache.searchCriteria)` re-run the live fetch — the root
//    cause of the "toggles don't refresh" bug.
//  - `selectedTypeFilter` overrides the per-type toggles.
//  - `persist()` round-trips the toggles and the per-TNS owner/prefix
//    strings through `UserDefaults`, and `init(for:)` reads them back.
//
//  The persistence tests touch `UserDefaults.standard` (the type uses it
//  directly), so setUp snapshots the relevant keys and tearDown restores
//  them — and a throwaway TNS name keeps the per-TNS dictionaries clean.
//

import XCTest
@testable import Macintora

final class DBCacheSearchCriteriaTests: XCTestCase {

    private static let testTNS = "__macintora_unit_test_tns__"
    private static let boolKeys = [
        "showTables", "showViews", "showIndexes", "showPackages",
        "showTypes", "showTriggers", "showProcedures", "showFunctions",
    ]
    private static let dictKeys = ["ownerList", "prefixList"]

    private var savedDefaults: [String: Any?] = [:]

    override func setUp() {
        super.setUp()
        let d = UserDefaults.standard
        for key in Self.boolKeys + Self.dictKeys {
            savedDefaults[key] = d.object(forKey: key)
        }
        // The type toggles are stored globally (not per-TNS), so a developer's
        // own saved prefs would otherwise leak in. Force a known all-on
        // baseline; tearDown restores whatever was there before.
        for key in Self.boolKeys { d.set(true, forKey: key) }
    }

    override func tearDown() {
        let d = UserDefaults.standard
        for (key, value) in savedDefaults {
            if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
        }
        savedDefaults = [:]
        super.tearDown()
    }

    // MARK: - Predicate reflects toggles

    func test_defaultCriteria_predicateIncludesEveryType() {
        let format = DBCacheSearchCriteria(for: Self.testTNS).predicate.predicateFormat
        for type in ["TABLE", "VIEW", "INDEX", "PACKAGE", "TYPE", "TRIGGER", "PROCEDURE", "FUNCTION"] {
            XCTAssertTrue(format.contains(type), "default predicate should include \(type); format = \(format)")
        }
    }

    func test_disablingTables_changesPredicateAndEquality() {
        var criteria = DBCacheSearchCriteria(for: Self.testTNS)
        let before = criteria
        criteria.showTables = false

        XCTAssertNotEqual(before, criteria, "flipping a type toggle must change the predicate so the list refreshes")
        XCTAssertFalse(criteria.predicate.predicateFormat.contains("TABLE"),
                       "TABLE should be gone once showTables is false; format = \(criteria.predicate.predicateFormat)")
    }

    func test_clearingAllTypeToggles_predicateHasNoTypeClause() {
        var criteria = DBCacheSearchCriteria(for: Self.testTNS)
        criteria.showTables = false
        criteria.showViews = false
        criteria.showIndexes = false
        criteria.showPackages = false
        criteria.showTypes = false
        criteria.showTriggers = false
        criteria.showProcedures = false
        criteria.showFunctions = false

        XCTAssertFalse(criteria.predicate.predicateFormat.contains("type_"),
                       "no type clause expected when every toggle is off; format = \(criteria.predicate.predicateFormat)")
    }

    func test_ignoreTypeFilter_dropsTypeClauseEntirely_butKeepsOtherClauses() {
        var criteria = DBCacheSearchCriteria(for: Self.testTNS)
        criteria.searchText = "RAISE_SALARY"
        criteria.ownerString = "HR"
        let before = criteria
        criteria.ignoreTypeFilter = true

        XCTAssertNotEqual(before, criteria, "toggling ignoreTypeFilter must change the predicate")
        let format = criteria.predicate.predicateFormat
        XCTAssertFalse(format.contains("type_"), "no type clause expected; format = \(format)")
        XCTAssertTrue(format.contains("name_ CONTAINS[c] \"RAISE_SALARY\""), "format = \(format)")
        XCTAssertTrue(format.contains("owner_ IN") && format.contains("HR"), "format = \(format)")
    }

    func test_selectedTypeFilter_winsOverIgnoreTypeFilter() {
        var criteria = DBCacheSearchCriteria(for: Self.testTNS)
        criteria.ignoreTypeFilter = true
        criteria.selectedTypeFilter = "PROCEDURE"

        let format = criteria.predicate.predicateFormat
        XCTAssertTrue(format.contains("type_ ==") && format.contains("PROCEDURE"), "format = \(format)")
    }

    func test_selectedTypeFilter_overridesToggles() {
        var criteria = DBCacheSearchCriteria(for: Self.testTNS)
        criteria.showViews = false                 // would normally drop VIEW
        criteria.selectedTypeFilter = "VIEW"

        let format = criteria.predicate.predicateFormat
        XCTAssertTrue(format.contains("type_ ==") && format.contains("VIEW"),
                      "forced filter should pin to VIEW; format = \(format)")
        XCTAssertFalse(format.contains("TABLE"),
                       "forced filter should not also include the toggle types; format = \(format)")
    }

    func test_searchText_addsContainsClause() {
        var criteria = DBCacheSearchCriteria(for: Self.testTNS)
        let before = criteria
        criteria.searchText = "EMP"

        XCTAssertNotEqual(before, criteria)
        XCTAssertTrue(criteria.predicate.predicateFormat.contains("name_ CONTAINS[c] \"EMP\""),
                      "format = \(criteria.predicate.predicateFormat)")
    }

    func test_ownerString_addsOwnerInClause_uppercasedAndSplit() {
        var criteria = DBCacheSearchCriteria(for: Self.testTNS)
        criteria.ownerString = "hr, scott"

        XCTAssertEqual(criteria.ownerInclusionList, ["HR", "SCOTT"])
        let format = criteria.predicate.predicateFormat
        XCTAssertTrue(format.contains("owner_ IN") && format.contains("HR") && format.contains("SCOTT"),
                      "format = \(format)")
    }

    func test_prefixString_addsBeginsWithClause() {
        var criteria = DBCacheSearchCriteria(for: Self.testTNS)
        criteria.prefixString = "dbms, dba"

        XCTAssertEqual(criteria.namePrefixInclusionList, ["DBMS", "DBA"])
        let format = criteria.predicate.predicateFormat
        XCTAssertTrue(format.contains("name_ BEGINSWITH[c] \"DBMS\""), "format = \(format)")
        XCTAssertTrue(format.contains("name_ BEGINSWITH[c] \"DBA\""), "format = \(format)")
    }

    func test_equality_comparesOnPredicateOnly() {
        let a = DBCacheSearchCriteria(for: "alpha")
        let b = DBCacheSearchCriteria(for: "beta")
        // Different TNS, identical filter state -> same predicate -> equal.
        XCTAssertEqual(a, b)
    }

    // MARK: - Persistence round-trip

    func test_persist_roundTripsTogglesAndPerTNSStrings() {
        var criteria = DBCacheSearchCriteria(for: Self.testTNS)
        criteria.showTriggers = false
        criteria.showFunctions = false
        criteria.ownerString = "HR"
        criteria.prefixString = "DBMS"
        criteria.persist()

        let reloaded = DBCacheSearchCriteria(for: Self.testTNS)
        XCTAssertFalse(reloaded.showTriggers)
        XCTAssertFalse(reloaded.showFunctions)
        XCTAssertTrue(reloaded.showTables, "untouched toggles should survive the round-trip")
        XCTAssertEqual(reloaded.ownerString, "HR")
        XCTAssertEqual(reloaded.prefixString, "DBMS")
    }

    func test_perTNSStrings_areKeyedByTNS() {
        var alpha = DBCacheSearchCriteria(for: "\(Self.testTNS).alpha")
        alpha.ownerString = "AONLY"
        alpha.persist()

        var beta = DBCacheSearchCriteria(for: "\(Self.testTNS).beta")
        beta.ownerString = "BONLY"
        beta.persist()

        XCTAssertEqual(DBCacheSearchCriteria(for: "\(Self.testTNS).alpha").ownerString, "AONLY")
        XCTAssertEqual(DBCacheSearchCriteria(for: "\(Self.testTNS).beta").ownerString, "BONLY")
    }
}
