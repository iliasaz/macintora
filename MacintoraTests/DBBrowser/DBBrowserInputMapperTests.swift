//
//  DBBrowserInputMapperTests.swift
//  MacintoraTests
//
//  Verifies `DBBrowserInputMapper.inputValue(from:mainConnection:)` produces the
//  correct `DBCacheInputValue` for each `ResolvedDBReference` case.
//

import XCTest
@testable import Macintora

final class DBBrowserInputMapperTests: XCTestCase {

    private let connection = MainConnection.preview()

    // MARK: - .schemaObject

    func test_schemaObject_withExplicitOwner() {
        let ref = ResolvedDBReference.schemaObject(owner: "HR", name: "EMPLOYEES")
        let value = DBBrowserInputMapper.inputValue(from: ref, mainConnection: connection)
        XCTAssertEqual(value.selectedOwner, "HR")
        XCTAssertEqual(value.selectedObjectName, "EMPLOYEES")
        XCTAssertNil(value.selectedObjectType)
        XCTAssertEqual(value.initialDetailTab, .details)
    }

    func test_schemaObject_nilOwner_passesNilOwner() {
        let ref = ResolvedDBReference.schemaObject(owner: nil, name: "DUAL")
        let value = DBBrowserInputMapper.inputValue(from: ref, mainConnection: connection)
        XCTAssertNil(value.selectedOwner)
        XCTAssertEqual(value.selectedObjectName, "DUAL")
        XCTAssertNil(value.selectedObjectType)
        XCTAssertEqual(value.initialDetailTab, .details)
    }

    // MARK: - .packageMember

    func test_packageMember_navigatesToParentPackage() {
        let ref = ResolvedDBReference.packageMember(
            packageOwner: "HR",
            packageName: "EMP_PKG",
            memberName: "GET_SALARY")
        let value = DBBrowserInputMapper.inputValue(from: ref, mainConnection: connection)
        XCTAssertEqual(value.selectedOwner, "HR")
        XCTAssertEqual(value.selectedObjectName, "EMP_PKG")
        XCTAssertEqual(value.selectedObjectType, OracleObjectType.package.rawValue)
        XCTAssertEqual(value.initialDetailTab, .details)
    }

    func test_packageMember_nilOwner_passesNil() {
        let ref = ResolvedDBReference.packageMember(
            packageOwner: nil,
            packageName: "UTIL_PKG",
            memberName: "HELPER")
        let value = DBBrowserInputMapper.inputValue(from: ref, mainConnection: connection)
        XCTAssertNil(value.selectedOwner)
        XCTAssertEqual(value.selectedObjectName, "UTIL_PKG")
        XCTAssertEqual(value.selectedObjectType, OracleObjectType.package.rawValue)
    }

    // MARK: - .column

    func test_column_navigatesToParentTable() {
        let ref = ResolvedDBReference.column(
            tableOwner: "HR",
            tableName: "EMPLOYEES",
            columnName: "SALARY")
        let value = DBBrowserInputMapper.inputValue(from: ref, mainConnection: connection)
        XCTAssertEqual(value.selectedOwner, "HR")
        XCTAssertEqual(value.selectedObjectName, "EMPLOYEES")
        XCTAssertEqual(value.selectedObjectType, OracleObjectType.table.rawValue)
        XCTAssertEqual(value.initialDetailTab, .details)
    }

    func test_column_nilOwner_passesNil() {
        let ref = ResolvedDBReference.column(
            tableOwner: nil,
            tableName: "DEPT",
            columnName: "DEPTNO")
        let value = DBBrowserInputMapper.inputValue(from: ref, mainConnection: connection)
        XCTAssertNil(value.selectedOwner)
        XCTAssertEqual(value.selectedObjectName, "DEPT")
    }

    // MARK: - .unresolved

    func test_unresolved_returnsBareBrowserValue() {
        let value = DBBrowserInputMapper.inputValue(from: .unresolved, mainConnection: connection)
        XCTAssertNil(value.selectedOwner)
        XCTAssertNil(value.selectedObjectName)
        XCTAssertNil(value.selectedObjectType)
        XCTAssertNil(value.initialDetailTab)
    }

    // MARK: - Connection identity

    func test_mainConnectionIsPreserved() {
        let ref = ResolvedDBReference.schemaObject(owner: nil, name: "X")
        let value = DBBrowserInputMapper.inputValue(from: ref, mainConnection: connection)
        XCTAssertEqual(value.mainConnection, connection)
    }
}
