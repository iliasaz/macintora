//
//  DBCacheCatalogScopeTests.swift
//  MacintoraTests
//
//  Covers the catalog-scope fix that lets a CONNECT/RESOURCE user populate the
//  DB cache without SELECT_CATALOG_ROLE or DBA views. `resolveCatalogScope()`
//  picks the dictionary-view prefix ("dba" when accessible, otherwise "all"),
//  and the query builders must emit that prefix on every catalog view so the
//  whole population path falls back to the ALL_* views together.
//
//  These tests exercise the pure SQL builders only — no live connection — by
//  passing the prefix explicitly. `includeSystemObjects` is forced off in
//  setUp (it's @AppStorage, so a developer's own pref would otherwise leak in
//  and change whether the `_users` subquery appears) and restored in tearDown.
//

import XCTest
@testable import Macintora

@MainActor
final class DBCacheCatalogScopeTests: XCTestCase {

    private var connDetails: ConnectionDetails!
    private var persistence: PersistenceController!
    private var vm: DBCacheVM!
    private var savedIncludeSystemObjects: Any?

    override func setUp() async throws {
        try await super.setUp()
        savedIncludeSystemObjects = UserDefaults.standard.object(forKey: "includeSystemObjects")
        UserDefaults.standard.set(false, forKey: "includeSystemObjects")
        connDetails = ConnectionDetails(username: "SCOTT", password: "", tns: "__catalog_scope_test__", connectionRole: .regular)
        persistence = PersistenceController(inMemory: true)
        vm = DBCacheVM(connDetails: connDetails, persistenceController: persistence)
        vm.searchCriteria.ownerString = ""
    }

    override func tearDown() async throws {
        if let savedIncludeSystemObjects {
            UserDefaults.standard.set(savedIncludeSystemObjects, forKey: "includeSystemObjects")
        } else {
            UserDefaults.standard.removeObject(forKey: "includeSystemObjects")
        }
        vm = nil
        persistence = nil
        connDetails = nil
        try await super.tearDown()
    }

    // MARK: - Default scope

    func test_catalogPrefix_defaultsToDBA() {
        // Until the scope is probed against a live connection, privileged
        // behavior (DBA_* views) is assumed.
        XCTAssertEqual(vm.catalogPrefix, "dba")
    }

    // MARK: - Object discovery query

    func test_objectQuery_dbaPrefix_usesDBAViews() {
        let sql = vm.buildObjectQuerySQL(prefix: "dba")
        XCTAssertTrue(sql.contains("from dba_objects o"), "expected DBA_OBJECTS; sql = \(sql)")
        XCTAssertTrue(sql.contains("from dba_users"), "expected DBA_USERS subquery; sql = \(sql)")
        XCTAssertFalse(sql.contains("all_objects"), "must not mix in ALL_* views; sql = \(sql)")
    }

    func test_objectQuery_allPrefix_usesAllViews_forLowPrivilegeUser() {
        let sql = vm.buildObjectQuerySQL(prefix: "all")
        XCTAssertTrue(sql.contains("from all_objects o"), "expected ALL_OBJECTS; sql = \(sql)")
        XCTAssertTrue(sql.contains("from all_users"), "expected ALL_USERS subquery; sql = \(sql)")
        XCTAssertFalse(sql.contains("dba_objects"), "must not fall back to DBA_* views; sql = \(sql)")
        XCTAssertFalse(sql.contains("dba_users"), "must not fall back to DBA_* views; sql = \(sql)")
    }

    func test_objectQuery_appliesOwnerInclusionList() {
        vm.searchCriteria.ownerString = "hr, scott"
        let sql = vm.buildObjectQuerySQL(prefix: "all")
        XCTAssertTrue(sql.contains("owner in ('HR','SCOTT')"),
                      "schemas the user typed must scope the population query; sql = \(sql)")
    }

    func test_objectQuery_noOwnerList_omitsOwnerClause() {
        vm.searchCriteria.ownerString = ""
        let sql = vm.buildObjectQuerySQL(prefix: "all")
        XCTAssertFalse(sql.contains("and owner in ("),
                       "blank schema list means every accessible schema; sql = \(sql)")
    }

    // MARK: - Cleanup query

    func test_cleanupQuery_honorsPrefix() {
        XCTAssertTrue(vm.buildCleanupCheckQuery(for: "1,2,3", prefix: "all").contains("from all_objects o"))
        XCTAssertTrue(vm.buildCleanupCheckQuery(for: "1,2,3", prefix: "dba").contains("from dba_objects o"))
    }
}
