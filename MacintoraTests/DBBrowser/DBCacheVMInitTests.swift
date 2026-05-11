//
//  DBCacheVMInitTests.swift
//  MacintoraTests
//
//  Verifies that `DBCacheVM.init` seeds `searchCriteria`, the pending-selection
//  fields, and `initialDetailTab` from the values passed at construction time.
//  Uses an in-memory `PersistenceController` so no disk I/O occurs.
//

import XCTest
@testable import Macintora

@MainActor
final class DBCacheVMInitTests: XCTestCase {

    private var connDetails: ConnectionDetails!
    private var persistence: PersistenceController!

    override func setUp() async throws {
        try await super.setUp()
        connDetails = ConnectionDetails(username: "SCOTT", password: "", tns: "orcl", connectionRole: .regular)
        persistence = PersistenceController(inMemory: true)
    }

    override func tearDown() async throws {
        connDetails = nil
        persistence = nil
        try await super.tearDown()
    }

    func test_defaultInit_leavesSelectionFieldsNil() {
        let vm = DBCacheVM(connDetails: connDetails,
                          persistenceController: persistence)
        XCTAssertNil(vm.pendingSelectionName)
        XCTAssertNil(vm.pendingSelectionOwner)
        XCTAssertNil(vm.pendingSelectionType)
        XCTAssertNil(vm.initialDetailTab)
    }

    func test_selectedObjectName_seedsSearchTextAndPending() {
        let vm = DBCacheVM(connDetails: connDetails,
                          persistenceController: persistence,
                          selectedObjectName: "EMPLOYEES")
        XCTAssertEqual(vm.searchCriteria.searchText, "EMPLOYEES")
        XCTAssertEqual(vm.pendingSelectionName, "EMPLOYEES")
    }

    func test_selectedObjectNameWithoutType_ignoresTypeFilter() {
        // A bare `owner.name` reference: the per-type toggles must not be
        // allowed to hide the requested object.
        let vm = DBCacheVM(connDetails: connDetails,
                          persistenceController: persistence,
                          selectedOwner: "HR",
                          selectedObjectName: "RAISE_SALARY") // a procedure, say
        XCTAssertTrue(vm.searchCriteria.ignoreTypeFilter)
        XCTAssertNil(vm.searchCriteria.selectedTypeFilter)
        XCTAssertFalse(vm.searchCriteria.predicate.predicateFormat.contains("type_"),
                       "predicate must not constrain by type; format = \(vm.searchCriteria.predicate.predicateFormat)")
    }

    func test_defaultInit_doesNotIgnoreTypeFilter() {
        let vm = DBCacheVM(connDetails: connDetails, persistenceController: persistence)
        XCTAssertFalse(vm.searchCriteria.ignoreTypeFilter)
    }

    func test_selectedOwner_seedsOwnerStringAndPending() {
        let vm = DBCacheVM(connDetails: connDetails,
                          persistenceController: persistence,
                          selectedOwner: "HR")
        XCTAssertEqual(vm.searchCriteria.ownerString, "HR")
        XCTAssertEqual(vm.pendingSelectionOwner, "HR")
    }

    func test_selectedObjectType_seedsTypeFilterAndPending() {
        let vm = DBCacheVM(connDetails: connDetails,
                          persistenceController: persistence,
                          selectedObjectType: "TABLE")
        XCTAssertEqual(vm.searchCriteria.selectedTypeFilter, "TABLE")
        XCTAssertEqual(vm.pendingSelectionType, "TABLE")
        // A known type pins via selectedTypeFilter, so the broad bypass stays off.
        XCTAssertFalse(vm.searchCriteria.ignoreTypeFilter)
    }

    func test_initialDetailTab_isStoredAndNotClearedByInit() {
        let vm = DBCacheVM(connDetails: connDetails,
                          persistenceController: persistence,
                          initialDetailTab: .details)
        XCTAssertEqual(vm.initialDetailTab, .details)
    }

    func test_allFieldsTogether() {
        let vm = DBCacheVM(connDetails: connDetails,
                          persistenceController: persistence,
                          selectedOwner: "HR",
                          selectedObjectName: "EMPLOYEES",
                          selectedObjectType: "TABLE",
                          initialDetailTab: .main)
        XCTAssertEqual(vm.searchCriteria.searchText, "EMPLOYEES")
        XCTAssertEqual(vm.searchCriteria.ownerString, "HR")
        XCTAssertEqual(vm.searchCriteria.selectedTypeFilter, "TABLE")
        XCTAssertEqual(vm.pendingSelectionName, "EMPLOYEES")
        XCTAssertEqual(vm.pendingSelectionOwner, "HR")
        XCTAssertEqual(vm.pendingSelectionType, "TABLE")
        XCTAssertEqual(vm.initialDetailTab, .main)
    }
}
