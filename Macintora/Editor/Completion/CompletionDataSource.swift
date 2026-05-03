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

    // MARK: - Quick View detail fetchers
    //
    // These read deeper than the completion popup needs and never participate
    // in autocompletion. They power the Quick View popover: one fetch per
    // user-triggered popup, returning a single Sendable struct that crosses
    // back to the main actor for SwiftUI rendering.

    /// Resolves a 1- or 2-part schema-object name to a concrete `(owner, name,
    /// type)` triple by consulting `DBCacheObject`. When `owner` is nil the
    /// preferred owner is tried first; if that misses, any cached schema is
    /// accepted (sorted by owner, name) and the first match wins.
    ///
    /// Returns `nil` when nothing matches — callers surface "not cached".
    func resolveSchemaObject(owner: String?,
                             name: String,
                             preferredOwner: String) async -> ResolvedSchemaObject? {
        await fetch { ctx -> ResolvedSchemaObject? in
            let upperName = name.uppercased()
            let upperPreferred = preferredOwner.uppercased()
            let request = DBCacheObject.fetchRequest()
            var predicates: [NSPredicate] = [
                NSPredicate(format: "name_ = %@", upperName)
            ]
            if let owner {
                predicates.append(NSPredicate(format: "owner_ = %@", owner.uppercased()))
            }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            request.sortDescriptors = [
                NSSortDescriptor(key: "owner_", ascending: true),
                NSSortDescriptor(key: "name_", ascending: true)
            ]
            do {
                let rows = try ctx.fetch(request)
                guard !rows.isEmpty else { return nil }
                // Prefer the connected schema if no explicit owner was given.
                let chosen: DBCacheObject = {
                    if owner != nil { return rows[0] }
                    return rows.first { ($0.owner_ ?? "") == upperPreferred } ?? rows[0]
                }()
                return ResolvedSchemaObject(
                    owner: chosen.owner_ ?? "",
                    name: chosen.name_ ?? "",
                    objectType: chosen.type_ ?? "UNKNOWN",
                    isValid: chosen.isValid,
                    lastDDLDate: chosen.lastDDLDate)
            } catch {
                self.logger.error("resolveSchemaObject fetch failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    /// Full table/view payload: row metadata + columns + indexes + triggers.
    /// Pass `highlightedColumn` to flag a specific column in the popover (used
    /// when the Quick View was triggered from a column reference).
    func tableDetail(owner: String,
                     name: String,
                     highlightedColumn: String?) async -> TableDetailPayload? {
        await fetch { ctx -> TableDetailPayload? in
            let upperOwner = owner.uppercased()
            let upperName = name.uppercased()

            let tableRequest = DBCacheTable.fetchRequest()
            tableRequest.predicate = NSPredicate(format: "owner_ = %@ AND name_ = %@",
                                                 upperOwner, upperName)
            tableRequest.fetchLimit = 1

            let columnRequest = DBCacheTableColumn.fetchRequest()
            columnRequest.predicate = NSPredicate(format: "owner_ = %@ AND tableName_ = %@",
                                                  upperOwner, upperName)
            columnRequest.sortDescriptors = [
                NSSortDescriptor(key: "internalColumnID", ascending: true)
            ]

            let indexRequest = DBCacheIndex.fetchRequest()
            indexRequest.predicate = NSPredicate(format: "tableOwner_ = %@ AND tableName_ = %@",
                                                 upperOwner, upperName)
            indexRequest.sortDescriptors = [NSSortDescriptor(key: "name_", ascending: true)]

            // `DBCacheTrigger` keys the parent table via `objectOwner` /
            // `objectName` (no trailing underscore on either) — it stores the
            // ALL_TRIGGERS BASE_OBJECT columns rather than mirroring the
            // table-side naming.
            let triggerRequest = DBCacheTrigger.fetchRequest()
            triggerRequest.predicate = NSPredicate(format: "objectOwner = %@ AND objectName = %@",
                                                   upperOwner, upperName)
            triggerRequest.sortDescriptors = [NSSortDescriptor(key: "name_", ascending: true)]

            do {
                let tableRow = try ctx.fetch(tableRequest).first
                let columnRows = try ctx.fetch(columnRequest)
                let indexRows = try ctx.fetch(indexRequest)
                let triggerRows = try ctx.fetch(triggerRequest)

                let columns = columnRows.map(self.makeColumn(from:))
                let indexes = indexRows.map { row in
                    QuickViewIndex(owner: row.owner_ ?? "",
                                   name: row.name_ ?? "",
                                   type: row.type_,
                                   isUnique: row.isUnique,
                                   isValid: row.isValid)
                }
                let triggers = triggerRows.map { row in
                    QuickViewTrigger(owner: row.owner_ ?? "",
                                     name: row.name_ ?? "",
                                     event: row.event_,
                                     isEnabled: row.isEnabled)
                }

                return TableDetailPayload(
                    owner: upperOwner,
                    name: upperName,
                    isView: tableRow?.isView ?? false,
                    isEditioning: tableRow?.isEditioning ?? false,
                    isReadOnly: tableRow?.isReadOnly ?? false,
                    isPartitioned: tableRow?.isPartitioned ?? false,
                    numRows: tableRow.flatMap { $0.numRows == 0 ? nil : Int64($0.numRows) },
                    lastAnalyzed: tableRow?.lastAnalyzed,
                    sqlText: tableRow?.sqltext,
                    columns: columns,
                    indexes: indexes,
                    triggers: triggers,
                    highlightedColumn: highlightedColumn?.uppercased())
            } catch {
                self.logger.error("tableDetail fetch failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    /// Single-column payload for the column mini-popover.
    func columnDetail(tableOwner: String?,
                      tableName: String,
                      columnName: String) async -> ColumnDetailPayload? {
        await fetch { ctx -> ColumnDetailPayload? in
            let upperTable = tableName.uppercased()
            let upperColumn = columnName.uppercased()
            let request = DBCacheTableColumn.fetchRequest()
            var predicates: [NSPredicate] = [
                NSPredicate(format: "tableName_ = %@", upperTable),
                NSPredicate(format: "columnName_ = %@", upperColumn)
            ]
            if let tableOwner {
                predicates.append(NSPredicate(format: "owner_ = %@", tableOwner.uppercased()))
            }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            request.fetchLimit = 1
            do {
                guard let row = try ctx.fetch(request).first else { return nil }
                return ColumnDetailPayload(
                    tableOwner: row.owner_ ?? "",
                    tableName: row.tableName_ ?? "",
                    column: self.makeColumn(from: row))
            } catch {
                self.logger.error("columnDetail fetch failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    /// Package or user-defined-type payload: spec source + member procedures
    /// with their argument signatures collapsed into a single Sendable struct.
    func packageDetail(owner: String, name: String) async -> PackageDetailPayload? {
        await fetch { ctx -> PackageDetailPayload? in
            let upperOwner = owner.uppercased()
            let upperName = name.uppercased()

            let objectRequest = DBCacheObject.fetchRequest()
            objectRequest.predicate = NSPredicate(format: "owner_ = %@ AND name_ = %@",
                                                  upperOwner, upperName)
            objectRequest.fetchLimit = 1

            let sourceRequest = DBCacheSource.fetchRequest()
            sourceRequest.predicate = NSPredicate(format: "owner_ = %@ AND name_ = %@",
                                                  upperOwner, upperName)
            sourceRequest.fetchLimit = 1

            let procRequest = DBCacheProcedure.fetchRequest()
            procRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "owner_ = %@", upperOwner),
                NSPredicate(format: "objectName_ = %@", upperName),
                NSPredicate(format: "procedureName_ != nil")
            ])
            procRequest.sortDescriptors = [
                NSSortDescriptor(key: "procedureName_", ascending: true),
                NSSortDescriptor(key: "overload_", ascending: true)
            ]

            let argRequest = DBCacheProcedureArgument.fetchRequest()
            argRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "owner_ = %@", upperOwner),
                NSPredicate(format: "objectName_ = %@", upperName),
                NSPredicate(format: "dataLevel == 0")
            ])
            argRequest.sortDescriptors = [
                NSSortDescriptor(key: "procedureName_", ascending: true),
                NSSortDescriptor(key: "overload_", ascending: true),
                NSSortDescriptor(key: "sequence", ascending: true)
            ]

            do {
                let objectRow = try ctx.fetch(objectRequest).first
                let sourceRow = try ctx.fetch(sourceRequest).first
                let procRows = try ctx.fetch(procRequest)
                let argRows = try ctx.fetch(argRequest)

                let procedures = self.assemblePackageProcedures(procRows: procRows,
                                                                argRows: argRows)
                let kind = objectRow?.type_ ?? "PACKAGE"
                return PackageDetailPayload(
                    owner: upperOwner,
                    name: upperName,
                    objectType: kind,
                    isValid: objectRow?.isValid ?? true,
                    specSource: sourceRow?.textSpec,
                    procedures: procedures)
            } catch {
                self.logger.error("packageDetail fetch failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    /// Single procedure / function payload — used both for standalone
    /// procedures (where `packageName` is nil) and package members. When
    /// multiple overloads exist and `overload` is nil, the lowest-numbered
    /// overload is returned (ALL_PROCEDURES.subprogram_id ordering).
    func procedureDetail(owner: String,
                         packageName: String?,
                         procedureName: String,
                         overload: String?) async -> ProcedureDetailPayload? {
        await fetch { ctx -> ProcedureDetailPayload? in
            let upperOwner = owner.uppercased()
            let upperProc = procedureName.uppercased()
            let upperPkgOrSelf = (packageName ?? procedureName).uppercased()

            let procRequest = DBCacheProcedure.fetchRequest()
            var procPredicates: [NSPredicate] = [
                NSPredicate(format: "owner_ = %@", upperOwner),
                NSPredicate(format: "objectName_ = %@", upperPkgOrSelf),
                NSPredicate(format: "procedureName_ = %@", upperProc)
            ]
            if let overload, !overload.isEmpty {
                procPredicates.append(NSPredicate(format: "overload_ = %@", overload))
            }
            procRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: procPredicates)
            procRequest.sortDescriptors = [NSSortDescriptor(key: "subprogramId", ascending: true)]
            procRequest.fetchLimit = 1

            // Parent DBCacheObject carries the validity bit. For package
            // members the parent is the package; for standalones it's the
            // procedure/function row itself. Treat a missing parent as
            // valid — same fallback as `packageDetail`.
            let objectRequest = DBCacheObject.fetchRequest()
            objectRequest.predicate = NSPredicate(format: "owner_ = %@ AND name_ = %@",
                                                  upperOwner, upperPkgOrSelf)
            objectRequest.fetchLimit = 1

            do {
                guard let procRow = try ctx.fetch(procRequest).first else { return nil }
                let objectRow = try ctx.fetch(objectRequest).first
                let procRowOverload = procRow.overload_

                let argRequest = DBCacheProcedureArgument.fetchRequest()
                var argPredicates: [NSPredicate] = [
                    NSPredicate(format: "owner_ = %@", upperOwner),
                    NSPredicate(format: "objectName_ = %@", upperPkgOrSelf),
                    NSPredicate(format: "procedureName_ = %@", upperProc),
                    NSPredicate(format: "dataLevel == 0")
                ]
                if let procRowOverload, !procRowOverload.isEmpty {
                    argPredicates.append(NSPredicate(format: "overload_ = %@", procRowOverload))
                } else {
                    argPredicates.append(NSPredicate(format: "overload_ == nil OR overload_ = %@", ""))
                }
                argRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: argPredicates)
                argRequest.sortDescriptors = [NSSortDescriptor(key: "sequence", ascending: true)]
                let argRows = try ctx.fetch(argRequest)

                var returnType: String? = nil
                var parameters: [QuickViewProcedureArgument] = []
                for arg in argRows {
                    if arg.position == 0, arg.argumentName_ == nil {
                        returnType = arg.dataType_
                        continue
                    }
                    parameters.append(QuickViewProcedureArgument(
                        sequence: Int(arg.sequence),
                        position: Int(arg.position),
                        name: arg.argumentName_,
                        dataType: arg.dataType_ ?? "",
                        inOut: arg.inOut_ ?? "IN",
                        defaulted: arg.defaulted,
                        defaultValue: arg.defaultValue_))
                }

                return ProcedureDetailPayload(
                    owner: procRow.owner_ ?? upperOwner,
                    name: procRow.procedureName_ ?? upperProc,
                    packageName: packageName.map { $0.uppercased() },
                    kind: returnType != nil ? "FUNCTION" : "PROCEDURE",
                    overload: procRowOverload,
                    returnType: returnType,
                    parameters: parameters,
                    isValid: objectRow?.isValid ?? true)
            } catch {
                self.logger.error("procedureDetail fetch failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    /// Returns metadata-only payload for object types we don't render in
    /// detail (TYPE, INDEX, TRIGGER, etc. when no specialised view exists).
    func unknownObjectDetail(owner: String, name: String) async -> UnknownObjectPayload? {
        await fetch { ctx -> UnknownObjectPayload? in
            let request = DBCacheObject.fetchRequest()
            request.predicate = NSPredicate(format: "owner_ = %@ AND name_ = %@",
                                            owner.uppercased(), name.uppercased())
            request.fetchLimit = 1
            do {
                guard let row = try ctx.fetch(request).first else { return nil }
                return UnknownObjectPayload(
                    owner: row.owner_ ?? "",
                    name: row.name_ ?? "",
                    objectType: row.type_ ?? "UNKNOWN",
                    isValid: row.isValid,
                    lastDDLDate: row.lastDDLDate)
            } catch {
                self.logger.error("unknownObjectDetail fetch failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    // MARK: - Internal helpers

    /// Translates a `DBCacheTableColumn` row into the Sendable view-model the
    /// popover renders. `nonisolated` because it operates entirely on `let`
    /// inputs and produces a value type — the actor's background context
    /// invokes it from inside `context.perform`.
    nonisolated private func makeColumn(from row: DBCacheTableColumn) -> QuickViewColumn {
        QuickViewColumn(
            columnID: Int32(row.columnID?.intValue ?? 0),
            columnName: row.columnName_ ?? "",
            dataType: row.dataType_ ?? "",
            dataTypeFormatted: Self.formatDataType(
                base: row.dataType_ ?? "",
                length: row.length,
                precision: row.precision?.int32Value ?? 0,
                scale: row.scale?.int32Value ?? 0),
            isNullable: row.isNullable,
            defaultValue: row.defaultValue,
            isIdentity: row.isIdentity,
            isVirtual: row.isVirtual,
            isHidden: row.isHidden)
    }

    /// Folds `(DBCacheProcedure, DBCacheProcedureArgument)` rows into the
    /// Sendable `QuickViewPackageProcedure` list. Skips the SUBPROGRAM_ID = 0
    /// "package itself" row that ALL_PROCEDURES emits and groups arguments
    /// by `(procedureName, overload)` so overloaded members render distinctly.
    nonisolated private func assemblePackageProcedures(
        procRows: [DBCacheProcedure],
        argRows: [DBCacheProcedureArgument]
    ) -> [QuickViewPackageProcedure] {
        struct Key: Hashable { let name: String; let overload: String }
        var groups: [Key: (kind: String,
                           overload: String?,
                           returnType: String?,
                           args: [QuickViewProcedureArgument])] = [:]
        for proc in procRows {
            guard let procName = proc.procedureName_, !procName.isEmpty else { continue }
            // Skip the package-self row (procedureName == package name AND
            // type == PACKAGE). Defensive — the predicate already excludes
            // procedureName_ == nil rows.
            if procName == proc.objectName_ && (proc.objectType_ ?? "") == "PACKAGE" {
                continue
            }
            let key = Key(name: procName, overload: proc.overload_ ?? "")
            if groups[key] == nil {
                groups[key] = (kind: "PROCEDURE",
                               overload: proc.overload_,
                               returnType: nil,
                               args: [])
            }
        }
        for arg in argRows {
            guard let procName = arg.procedureName_, !procName.isEmpty else { continue }
            let key = Key(name: procName, overload: arg.overload_ ?? "")
            guard var bucket = groups[key] else { continue }
            if arg.position == 0, arg.argumentName_ == nil {
                bucket.returnType = arg.dataType_
                bucket.kind = "FUNCTION"
            } else if arg.position > 0 {
                bucket.args.append(QuickViewProcedureArgument(
                    sequence: Int(arg.sequence),
                    position: Int(arg.position),
                    name: arg.argumentName_,
                    dataType: arg.dataType_ ?? "",
                    inOut: arg.inOut_ ?? "IN",
                    defaulted: arg.defaulted,
                    defaultValue: arg.defaultValue_))
            }
            groups[key] = bucket
        }
        return groups
            .map { key, value in
                QuickViewPackageProcedure(
                    name: key.name,
                    kind: value.kind,
                    overload: value.overload,
                    returnType: value.returnType,
                    parameters: value.args)
            }
            .sorted { lhs, rhs in
                if lhs.name != rhs.name { return lhs.name < rhs.name }
                return (lhs.overload ?? "") < (rhs.overload ?? "")
            }
    }

    /// Oracle-style data-type pretty-printer. Returns `VARCHAR2(120)`,
    /// `NUMBER(10,2)`, `NUMBER`, etc. — a compact form that fits the popover.
    nonisolated static func formatDataType(base: String,
                                           length: Int32,
                                           precision: Int32,
                                           scale: Int32) -> String {
        let upper = base.uppercased()
        switch upper {
        case "VARCHAR2", "VARCHAR", "CHAR", "NVARCHAR2", "NCHAR", "RAW":
            return length > 0 ? "\(upper)(\(length))" : upper
        case "NUMBER":
            if precision > 0 && scale > 0 {
                return "NUMBER(\(precision),\(scale))"
            }
            if precision > 0 {
                return "NUMBER(\(precision))"
            }
            return "NUMBER"
        case "FLOAT":
            return precision > 0 ? "FLOAT(\(precision))" : "FLOAT"
        default:
            return upper
        }
    }
}

/// Lightweight result of `resolveSchemaObject(...)` — what the cache says
/// about a schema-qualified name lookup. Quick View's controller pivots on
/// `objectType` to pick which detail fetch to run next.
struct ResolvedSchemaObject: Sendable, Equatable {
    let owner: String
    let name: String
    let objectType: String
    let isValid: Bool
    let lastDDLDate: Date?
}
