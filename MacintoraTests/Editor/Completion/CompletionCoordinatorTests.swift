//
//  CompletionCoordinatorTests.swift
//  MacintoraTests
//
//  Exercises `CompletionCoordinator.dottedMemberSuggestions` against an
//  in-memory CoreData store. Phase 1 of issue #10: typing `pkg.` must
//  surface the cached package's procedures and functions while still
//  showing schema-scoped objects when the qualifier collides with a
//  schema name.
//

import XCTest
import CoreData
@testable import Macintora

@MainActor
final class CompletionCoordinatorTests: XCTestCase {

    private var persistence: PersistenceController!
    private var dataSource: CompletionDataSource!
    private var coordinator: CompletionCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        persistence = PersistenceController(inMemory: true)
        dataSource = CompletionDataSource(persistenceController: persistence)
        coordinator = CompletionCoordinator(
            treeStore: SQLTreeStore(),
            dataSource: dataSource,
            defaultOwnerProvider: { "HR" })
    }

    override func tearDown() async throws {
        coordinator = nil
        dataSource = nil
        persistence = nil
        try await super.tearDown()
    }

    // MARK: - Phase 1: package members on `pkg.`

    func test_dottedMember_packageQualifier_listsProcedureMembers() async {
        seedAccountsPackageWithObject(owner: "HR")

        let items = await coordinator.dottedMemberSuggestions(
            qualifier: "ACCOUNTS_PKG", prefix: "",
            owner: "HR", source: "", tree: nil, offset: 0)

        let names = Set(items.map(\.displayText))
        XCTAssertTrue(names.contains("GET_BALANCE"))
        XCTAssertTrue(names.contains("DEBIT"),
                      "Both DEBIT overloads should be present (one row each)")
        XCTAssertEqual(items.filter { $0.displayText == "DEBIT" }.count, 2,
                       "Each overload renders as its own popup row")
    }

    func test_dottedMember_packageQualifier_filtersByPrefix() async {
        seedAccountsPackageWithObject(owner: "HR")

        let items = await coordinator.dottedMemberSuggestions(
            qualifier: "ACCOUNTS_PKG", prefix: "GET",
            owner: "HR", source: "", tree: nil, offset: 0)

        XCTAssertEqual(items.map(\.displayText), ["GET_BALANCE"])
    }

    func test_dottedMember_packageQualifier_caseInsensitive() async {
        // User typed `accounts_pkg.` — the cache stores upper-case names; the
        // qualifier must be normalised before the lookup.
        seedAccountsPackageWithObject(owner: "HR")

        let items = await coordinator.dottedMemberSuggestions(
            qualifier: "accounts_pkg", prefix: "",
            owner: "HR", source: "", tree: nil, offset: 0)

        XCTAssertFalse(items.isEmpty)
        XCTAssertTrue(items.contains { $0.displayText == "GET_BALANCE" })
    }

    func test_dottedMember_unresolvedQualifier_returnsEmpty() async {
        // No cached schema, no cached package, no cached table by this name —
        // dotted-member completion should produce nothing rather than dump
        // the cache.
        let items = await coordinator.dottedMemberSuggestions(
            qualifier: "MYSTERY_PKG", prefix: "",
            owner: "HR", source: "", tree: nil, offset: 0)
        XCTAssertTrue(items.isEmpty)
    }

    func test_dottedMember_schemaQualifier_unaffectedByPackageProbe() async {
        // `HR.` should still list HR's tables/views/packages. The new package
        // probe runs in parallel; it must not suppress this result.
        let ctx = persistence.container.viewContext
        addObject(in: ctx, owner: "HR", name: "EMPLOYEES", type: "TABLE")
        addObject(in: ctx, owner: "HR", name: "DEPARTMENTS", type: "TABLE")
        try! ctx.save()

        let items = await coordinator.dottedMemberSuggestions(
            qualifier: "HR", prefix: "",
            owner: "HR", source: "", tree: nil, offset: 0)

        let names = Set(items.map(\.displayText))
        XCTAssertTrue(names.contains("EMPLOYEES"))
        XCTAssertTrue(names.contains("DEPARTMENTS"))
    }

    func test_dottedMember_qualifierIsBothSchemaAndPackage_mergesResults() async {
        // Edge case: the same identifier names a schema (with at least one
        // table inside) AND a package in another schema. Showing both kinds
        // is the pragmatic answer when the analyzer can't disambiguate.
        let ctx = persistence.container.viewContext
        // BILLING owns a TABLE called "ACCOUNTS_PKG" (silly but legal).
        addObject(in: ctx, owner: "ACCOUNTS_PKG", name: "LEDGER", type: "TABLE")
        try! ctx.save()
        seedAccountsPackageWithObject(owner: "HR")

        let items = await coordinator.dottedMemberSuggestions(
            qualifier: "ACCOUNTS_PKG", prefix: "",
            owner: "HR", source: "", tree: nil, offset: 0)

        let names = Set(items.map(\.displayText))
        XCTAssertTrue(names.contains("LEDGER"),
                      "Schema-scoped objects must still surface")
        XCTAssertTrue(names.contains("GET_BALANCE"),
                      "Package members must surface alongside schema objects")
    }

    func test_dottedMember_packageInOtherSchema_resolvesViaPreferredOwner() async {
        // Package only exists in BILLING; preferred owner is HR. The probe
        // must still find it via the alphabetical-fallback branch of
        // resolvePackage.
        seedAccountsPackageWithObject(owner: "BILLING")

        let items = await coordinator.dottedMemberSuggestions(
            qualifier: "ACCOUNTS_PKG", prefix: "",
            owner: "HR", source: "", tree: nil, offset: 0)

        XCTAssertTrue(items.contains { $0.displayText == "GET_BALANCE" })
    }

    // MARK: - Seed helpers

    /// Adds the same `DBCacheProcedure` / `DBCacheProcedureArgument` rows as
    /// `CompletionDataSourceTests.seedAccountsPackage`, plus a parent
    /// `DBCacheObject(type: "PACKAGE")` so `resolvePackage` can find it.
    private func seedAccountsPackageWithObject(owner: String) {
        let ctx = persistence.container.viewContext

        let pkgObject = DBCacheObject(context: ctx)
        pkgObject.owner_ = owner
        pkgObject.name_ = "ACCOUNTS_PKG"
        pkgObject.type_ = "PACKAGE"

        addProcedure(in: ctx, owner: owner, pkg: "ACCOUNTS_PKG",
                     name: nil, subprogramId: 0, overload: nil,
                     parentType: "PACKAGE")
        addProcedure(in: ctx, owner: owner, pkg: "ACCOUNTS_PKG",
                     name: "GET_BALANCE", subprogramId: 1, overload: nil,
                     parentType: "PACKAGE")
        addProcedure(in: ctx, owner: owner, pkg: "ACCOUNTS_PKG",
                     name: "DEBIT", subprogramId: 2, overload: "1",
                     parentType: "PACKAGE")
        addProcedure(in: ctx, owner: owner, pkg: "ACCOUNTS_PKG",
                     name: "DEBIT", subprogramId: 3, overload: "2",
                     parentType: "PACKAGE")

        addArgument(in: ctx, owner: owner, pkg: "ACCOUNTS_PKG", proc: "GET_BALANCE",
                    overload: nil, position: 0, sequence: 1, name: nil,
                    dataType: "NUMBER", inOut: "OUT")
        addArgument(in: ctx, owner: owner, pkg: "ACCOUNTS_PKG", proc: "GET_BALANCE",
                    overload: nil, position: 1, sequence: 2, name: "ACCT_ID",
                    dataType: "NUMBER", inOut: "IN")
        addArgument(in: ctx, owner: owner, pkg: "ACCOUNTS_PKG", proc: "DEBIT",
                    overload: "1", position: 1, sequence: 1, name: "AMOUNT",
                    dataType: "NUMBER", inOut: "IN")
        addArgument(in: ctx, owner: owner, pkg: "ACCOUNTS_PKG", proc: "DEBIT",
                    overload: "2", position: 1, sequence: 1, name: "AMOUNT",
                    dataType: "NUMBER", inOut: "IN")
        addArgument(in: ctx, owner: owner, pkg: "ACCOUNTS_PKG", proc: "DEBIT",
                    overload: "2", position: 2, sequence: 2, name: "CURRENCY",
                    dataType: "VARCHAR2", inOut: "IN")

        try! ctx.save()
    }

    private func addObject(in ctx: NSManagedObjectContext,
                           owner: String, name: String, type: String) {
        let row = DBCacheObject(context: ctx)
        row.owner_ = owner
        row.name_ = name
        row.type_ = type
    }

    private func addProcedure(in ctx: NSManagedObjectContext,
                              owner: String, pkg: String, name: String?,
                              subprogramId: Int32, overload: String?,
                              parentType: String) {
        let row = DBCacheProcedure(context: ctx)
        row.owner_ = owner
        row.objectName_ = pkg
        row.procedureName_ = name
        row.objectType_ = parentType
        row.subprogramId = subprogramId
        row.overload_ = overload
    }

    private func addArgument(in ctx: NSManagedObjectContext,
                             owner: String, pkg: String, proc: String,
                             overload: String?, position: Int16, sequence: Int16,
                             name: String?, dataType: String, inOut: String) {
        let row = DBCacheProcedureArgument(context: ctx)
        row.owner_ = owner
        row.objectName_ = pkg
        row.procedureName_ = proc
        row.overload_ = overload
        row.position = position
        row.sequence = sequence
        row.dataLevel = 0
        row.argumentName_ = name
        row.dataType_ = dataType
        row.inOut_ = inOut
    }
}
