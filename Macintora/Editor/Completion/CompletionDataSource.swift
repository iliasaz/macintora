//
//  CompletionDataSource.swift
//  Macintora
//
//  Background-context CoreData reader for the editor's autocompletion popup.
//  All fetches return Sendable plain structs (never `NSManagedObject`s) so
//  results can cross actor boundaries safely. Holds its own background
//  context for the lifetime of the editor instance.
//

import Foundation
import CoreData
import os

actor CompletionDataSource {

    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext
    private let logger = Logger(subsystem: "com.iliasazonov.macintora",
                                category: "completion.datasource")

    init(persistenceController: PersistenceController) {
        self.container = persistenceController.container
        self.context = persistenceController.container.newBackgroundContext()
        self.context.name = "completion-datasource"
    }

    /// Tables/views whose name **contains** `search` (case-insensitive).
    /// Sourced from `DBCacheObject` (filtered by `type_ IN ("TABLE", "VIEW")`),
    /// which is the comprehensive catalog the DB browser shows. Reading from
    /// `DBCacheTable` would miss any table whose details haven't been
    /// fetched yet.
    ///
    /// Returns matches across every cached schema; the connected schema is
    /// sorted first as a relevance hint (NOT a filter), and prefix matches
    /// rank above infix matches so a typed `EMP` still puts `EMPLOYEES`
    /// ahead of `XYZ_EMP`. Empty `search` is scoped to `preferredOwner` only
    /// to avoid dumping the entire cache.
    func tables(search: String,
                preferredOwner: String,
                limit: Int) async -> [TableSuggestion] {
        await fetch { ctx -> [TableSuggestion] in
            let request = DBCacheObject.fetchRequest()
            let upperSearch = search.uppercased()
            let upperOwner = preferredOwner.uppercased()
            // Anything you can SELECT from in the FROM clause. Oracle's
            // ALL_OBJECTS.object_type uses the literal strings below; we
            // include synonyms because they typically resolve to a table or
            // view the user wants to query.
            var predicates: [NSPredicate] = [
                NSPredicate(format: "type_ IN %@",
                            ["TABLE", "VIEW", "MATERIALIZED VIEW", "SYNONYM"])
            ]
            if upperSearch.isEmpty {
                predicates.append(NSPredicate(format: "owner_ = %@", upperOwner))
            } else {
                predicates.append(NSPredicate(format: "name_ CONTAINS[c] %@", upperSearch))
            }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            request.sortDescriptors = [
                NSSortDescriptor(key: "owner_", ascending: true),
                NSSortDescriptor(key: "name_", ascending: true)
            ]
            // Pull a wider candidate set than the popup limit so the
            // prefix-first / preferred-owner-first reordering done in Swift
            // below doesn't get truncated to a noisy slice.
            request.fetchLimit = max(limit * 4, limit)
            do {
                let rows = try ctx.fetch(request)
                let suggestions = rows.map { row in
                    TableSuggestion(
                        owner: row.owner_ ?? "",
                        name: row.name_ ?? "",
                        objectType: row.type_ ?? "TABLE")
                }
                return self.rank(suggestions,
                                 name: \.name,
                                 owner: \.owner,
                                 search: upperSearch,
                                 preferredOwner: upperOwner,
                                 limit: limit)
            } catch {
                self.logger.error("tables fetch failed: \(error.localizedDescription, privacy: .public)")
                return []
            }
        }
    }

    /// Columns of a specific table. `search` is matched as a case-insensitive
    /// substring against the column name. When `owner` is nil the query is
    /// open to every schema with a matching table (relevant when the user
    /// typed an alias whose backing table couldn't be schema-disambiguated).
    func columns(tableName: String,
                 owner: String?,
                 search: String,
                 limit: Int) async -> [ColumnSuggestion] {
        await fetch { ctx -> [ColumnSuggestion] in
            let request = DBCacheTableColumn.fetchRequest()
            let upperTable = tableName.uppercased()
            let upperSearch = search.uppercased()
            var predicates: [NSPredicate] = [
                NSPredicate(format: "tableName_ = %@", upperTable)
            ]
            if let owner {
                predicates.append(NSPredicate(format: "owner_ = %@", owner.uppercased()))
            }
            if !upperSearch.isEmpty {
                predicates.append(NSPredicate(format: "columnName_ CONTAINS[c] %@", upperSearch))
            }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            // Wider fetch so the prefix-first re-rank below has material to
            // sort.
            request.fetchLimit = max(limit * 4, limit)
            do {
                let rows = try ctx.fetch(request)
                let suggestions = rows.map { row in
                    ColumnSuggestion(
                        owner: row.owner_ ?? "",
                        tableName: row.tableName_ ?? "",
                        columnName: row.columnName_ ?? "",
                        dataType: row.dataType_ ?? "")
                }
                return self.rankByPrefixThenInfix(suggestions,
                                                  name: \.columnName,
                                                  search: upperSearch,
                                                  limit: limit)
            } catch {
                self.logger.error("columns fetch failed: \(error.localizedDescription, privacy: .public)")
                return []
            }
        }
    }

    /// Objects (tables, views, packages, etc.). `search` is a case-insensitive
    /// substring match against the name. When `owner` is non-nil the query
    /// is strictly scoped to that schema — used for `schema.<search>`. When
    /// `owner` is nil the query spans every schema and the `preferredOwner`
    /// (if any) is sorted first; prefix matches still rank above infix.
    func objects(search: String,
                 owner: String?,
                 preferredOwner: String? = nil,
                 types: [String],
                 limit: Int) async -> [ObjectSuggestion] {
        await fetch { ctx -> [ObjectSuggestion] in
            let request = DBCacheObject.fetchRequest()
            let upperSearch = search.uppercased()
            var predicates: [NSPredicate] = []
            if let owner {
                predicates.append(NSPredicate(format: "owner_ = %@", owner.uppercased()))
            }
            if !upperSearch.isEmpty {
                predicates.append(NSPredicate(format: "name_ CONTAINS[c] %@", upperSearch))
            }
            if !types.isEmpty {
                predicates.append(NSPredicate(format: "type_ IN %@", types))
            }
            if !predicates.isEmpty {
                request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            }
            request.sortDescriptors = [
                NSSortDescriptor(key: "type_", ascending: true),
                NSSortDescriptor(key: "name_", ascending: true)
            ]
            request.fetchLimit = max(limit * 4, limit)
            do {
                let rows = try ctx.fetch(request)
                let suggestions = rows.map { row in
                    ObjectSuggestion(
                        owner: row.owner_ ?? "",
                        name: row.name_ ?? "",
                        type: row.type_ ?? "")
                }
                if owner != nil {
                    // Strict-owner case: just rank by prefix-vs-infix.
                    return self.rankByPrefixThenInfix(suggestions,
                                                     name: \.name,
                                                     search: upperSearch,
                                                     limit: limit)
                }
                let preferred = preferredOwner?.uppercased() ?? ""
                return self.rank(suggestions,
                                 name: \.name,
                                 owner: \.owner,
                                 search: upperSearch,
                                 preferredOwner: preferred,
                                 limit: limit)
            } catch {
                self.logger.error("objects fetch failed: \(error.localizedDescription, privacy: .public)")
                return []
            }
        }
    }

    /// Procedures and functions that belong to `packageName` (for package
    /// members) or whose own object name equals `packageName` (for standalones).
    /// `search` is matched as a case-insensitive substring against the member
    /// name. The kind ("PROCEDURE" / "FUNCTION") and `returnType` are derived
    /// from a parallel fetch on `DBCacheProcedureArgument` rows where
    /// `position == 0 && dataLevel == 0` — that row exists only for functions
    /// and carries the return type, so its absence flags a procedure.
    func procedures(packageName: String,
                    owner: String?,
                    search: String,
                    limit: Int) async -> [ProcedureSuggestion] {
        await fetch { ctx -> [ProcedureSuggestion] in
            let upperPkg = packageName.uppercased()
            let upperSearch = search.uppercased()

            // 1. Procedures.
            let procRequest = DBCacheProcedure.fetchRequest()
            var procPredicates: [NSPredicate] = [
                NSPredicate(format: "objectName_ = %@", upperPkg),
                NSPredicate(format: "procedureName_ != nil")
            ]
            if let owner {
                procPredicates.append(NSPredicate(format: "owner_ = %@", owner.uppercased()))
            }
            if !upperSearch.isEmpty {
                procPredicates.append(NSPredicate(format: "procedureName_ CONTAINS[c] %@", upperSearch))
            }
            procRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: procPredicates)
            procRequest.sortDescriptors = [
                NSSortDescriptor(key: "procedureName_", ascending: true),
                NSSortDescriptor(key: "overload_", ascending: true)
            ]
            procRequest.fetchLimit = max(limit * 4, limit)

            // 2. Return-type rows (one fetch, dictionary-keyed lookup below).
            let argRequest = DBCacheProcedureArgument.fetchRequest()
            var argPredicates: [NSPredicate] = [
                NSPredicate(format: "objectName_ = %@", upperPkg),
                NSPredicate(format: "position == 0"),
                NSPredicate(format: "dataLevel == 0"),
                NSPredicate(format: "argumentName_ == nil")
            ]
            if let owner {
                argPredicates.append(NSPredicate(format: "owner_ = %@", owner.uppercased()))
            }
            argRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: argPredicates)

            do {
                let procRows = try ctx.fetch(procRequest)
                let argRows = try ctx.fetch(argRequest)
                struct ReturnKey: Hashable { let owner, name, overload: String }
                var returnTypes: [ReturnKey: String] = [:]
                for arg in argRows {
                    let key = ReturnKey(
                        owner: arg.owner_ ?? "",
                        name: arg.procedureName_ ?? "",
                        overload: arg.overload_ ?? ""
                    )
                    returnTypes[key] = arg.dataType_ ?? ""
                }
                let suggestions: [ProcedureSuggestion] = procRows.compactMap { row in
                    guard let procName = row.procedureName_, !procName.isEmpty,
                          let pkg = row.objectName_ else { return nil }
                    // Skip the SUBPROGRAM_ID = 0 package-itself row that
                    // ALL_PROCEDURES emits (procedureName == objectName).
                    if procName == pkg && (row.objectType_ ?? "") == "PACKAGE" {
                        return nil
                    }
                    let key = ReturnKey(
                        owner: row.owner_ ?? "",
                        name: procName,
                        overload: row.overload_ ?? ""
                    )
                    let returnType = returnTypes[key]
                    return ProcedureSuggestion(
                        owner: row.owner_ ?? "",
                        packageName: pkg,
                        procedureName: procName,
                        overload: row.overload_,
                        subprogramId: Int(row.subprogramId),
                        kind: returnType != nil ? "FUNCTION" : "PROCEDURE",
                        parentType: row.objectType_ ?? "",
                        returnType: returnType
                    )
                }
                return self.rankByPrefixThenInfix(suggestions,
                                                  name: \.procedureName,
                                                  search: upperSearch,
                                                  limit: limit)
            } catch {
                self.logger.error("procedures fetch failed: \(error.localizedDescription, privacy: .public)")
                return []
            }
        }
    }

    /// Arguments of a single procedure / function invocation. Excludes the
    /// `position == 0` return-value row (callers consume return type via
    /// `procedures(...).returnType`) and `dataLevel > 0` composite expansions.
    func procedureArguments(owner: String,
                            packageName: String,
                            procedureName: String,
                            overload: String?) async -> [ProcedureArgumentSuggestion] {
        await fetch { ctx -> [ProcedureArgumentSuggestion] in
            let request = DBCacheProcedureArgument.fetchRequest()
            var predicates: [NSPredicate] = [
                NSPredicate(format: "owner_ = %@", owner.uppercased()),
                NSPredicate(format: "objectName_ = %@", packageName.uppercased()),
                NSPredicate(format: "procedureName_ = %@", procedureName.uppercased()),
                NSPredicate(format: "dataLevel == 0"),
                NSPredicate(format: "position > 0")
            ]
            if let overload, !overload.isEmpty {
                predicates.append(NSPredicate(format: "overload_ = %@", overload))
            } else {
                predicates.append(NSPredicate(format: "overload_ == nil OR overload_ = %@", ""))
            }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            request.sortDescriptors = [NSSortDescriptor(key: "sequence", ascending: true)]
            do {
                let rows = try ctx.fetch(request)
                return rows.map { row in
                    ProcedureArgumentSuggestion(
                        owner: row.owner_ ?? "",
                        packageName: row.objectName_ ?? "",
                        procedureName: row.procedureName_ ?? "",
                        overload: row.overload_,
                        position: Int(row.position),
                        argumentName: row.argumentName_,
                        dataType: row.dataType_ ?? "",
                        inOut: row.inOut_ ?? "IN",
                        defaulted: row.defaulted,
                        defaultValue: row.defaultValue_
                    )
                }
            } catch {
                self.logger.error("procedureArguments fetch failed: \(error.localizedDescription, privacy: .public)")
                return []
            }
        }
    }

    /// Two-tier rank for a list returned by a `CONTAINS[c]` predicate:
    /// 1. name-prefix matches first, infix matches after;
    /// 2. within each tier, rows whose owner equals `preferredOwner` first.
    /// Stable within tiers (CoreData's sort order is preserved). Truncated
    /// to `limit`. `nonisolated` because the helper is pure and called from
    /// the actor's background `context.perform` closure.
    nonisolated private func rank<T>(_ rows: [T],
                                     name: KeyPath<T, String>,
                                     owner: KeyPath<T, String>,
                                     search: String,
                                     preferredOwner: String,
                                     limit: Int) -> [T] {
        guard !search.isEmpty else {
            return ownerFirst(rows, owner: owner, preferredOwner: preferredOwner, limit: limit)
        }
        var prefixHits: [T] = []
        var infixHits: [T] = []
        for row in rows {
            if row[keyPath: name].uppercased().hasPrefix(search) {
                prefixHits.append(row)
            } else {
                infixHits.append(row)
            }
        }
        let prefixOrdered = ownerFirst(prefixHits, owner: owner, preferredOwner: preferredOwner, limit: limit)
        let infixOrdered = ownerFirst(infixHits, owner: owner, preferredOwner: preferredOwner, limit: limit)
        return Array((prefixOrdered + infixOrdered).prefix(limit))
    }

    /// Same idea as `rank(_:name:owner:search:preferredOwner:limit:)` but
    /// without the owner-tier — used when the caller has already constrained
    /// by owner (e.g. `schema.<search>`).
    nonisolated private func rankByPrefixThenInfix<T>(_ rows: [T],
                                                      name: KeyPath<T, String>,
                                                      search: String,
                                                      limit: Int) -> [T] {
        guard !search.isEmpty else { return Array(rows.prefix(limit)) }
        var prefixHits: [T] = []
        var infixHits: [T] = []
        for row in rows {
            if row[keyPath: name].uppercased().hasPrefix(search) {
                prefixHits.append(row)
            } else {
                infixHits.append(row)
            }
        }
        return Array((prefixHits + infixHits).prefix(limit))
    }

    nonisolated private func ownerFirst<T>(_ rows: [T],
                                           owner: KeyPath<T, String>,
                                           preferredOwner: String,
                                           limit: Int) -> [T] {
        guard !preferredOwner.isEmpty else { return Array(rows.prefix(limit)) }
        var preferred: [T] = []
        var others: [T] = []
        for row in rows {
            if row[keyPath: owner] == preferredOwner {
                preferred.append(row)
            } else {
                others.append(row)
            }
        }
        return Array((preferred + others).prefix(limit))
    }

    // MARK: - Background-context wrapper

    /// Runs `body` on the background context and returns its result. Wraps
    /// `context.perform` in a continuation so the actor can `await` the
    /// CoreData callback.
    private func fetch<T: Sendable>(_ body: @escaping @Sendable (NSManagedObjectContext) -> T) async -> T {
        let context = self.context
        return await withCheckedContinuation { continuation in
            context.perform {
                let result = body(context)
                continuation.resume(returning: result)
            }
        }
    }
}
