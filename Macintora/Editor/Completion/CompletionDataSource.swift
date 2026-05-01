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

    /// Tables/views whose name starts with `prefix`. Searches the user's
    /// schema first; callers may run a second query for a different owner.
    func tables(prefix: String,
                defaultOwner: String,
                limit: Int) async -> [TableSuggestion] {
        await fetch { ctx -> [TableSuggestion] in
            let request = DBCacheTable.fetchRequest()
            let upperPrefix = prefix.uppercased()
            let upperOwner = defaultOwner.uppercased()
            if upperPrefix.isEmpty {
                request.predicate = NSPredicate(format: "owner_ = %@", upperOwner)
            } else {
                request.predicate = NSPredicate(
                    format: "owner_ = %@ AND name_ BEGINSWITH[c] %@",
                    upperOwner, upperPrefix)
            }
            request.sortDescriptors = [NSSortDescriptor(key: "name_", ascending: true)]
            request.fetchLimit = limit
            do {
                let rows = try ctx.fetch(request)
                return rows.map { row in
                    TableSuggestion(
                        owner: row.owner_ ?? "",
                        name: row.name_ ?? "",
                        isView: row.isView)
                }
            } catch {
                self.logger.error("tables fetch failed: \(error.localizedDescription, privacy: .public)")
                return []
            }
        }
    }

    /// Columns of a specific table. `owner` defaults to whatever was saved on
    /// the cached row when nil.
    func columns(tableName: String,
                 owner: String?,
                 prefix: String,
                 limit: Int) async -> [ColumnSuggestion] {
        await fetch { ctx -> [ColumnSuggestion] in
            let request = DBCacheTableColumn.fetchRequest()
            let upperTable = tableName.uppercased()
            let upperPrefix = prefix.uppercased()
            var predicates: [NSPredicate] = [
                NSPredicate(format: "tableName_ = %@", upperTable)
            ]
            if let owner {
                predicates.append(NSPredicate(format: "owner_ = %@", owner.uppercased()))
            }
            if !upperPrefix.isEmpty {
                predicates.append(NSPredicate(format: "columnName_ BEGINSWITH[c] %@", upperPrefix))
            }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            request.fetchLimit = limit
            do {
                let rows = try ctx.fetch(request)
                return rows.map { row in
                    ColumnSuggestion(
                        owner: row.owner_ ?? "",
                        tableName: row.tableName_ ?? "",
                        columnName: row.columnName_ ?? "",
                        dataType: row.dataType_ ?? "")
                }
            } catch {
                self.logger.error("columns fetch failed: \(error.localizedDescription, privacy: .public)")
                return []
            }
        }
    }

    /// Objects (tables, views, packages, etc.) for `owner.prefix...` style
    /// completion (e.g. when the user types `HR.`).
    func objects(prefix: String,
                 owner: String?,
                 types: [String],
                 limit: Int) async -> [ObjectSuggestion] {
        await fetch { ctx -> [ObjectSuggestion] in
            let request = DBCacheObject.fetchRequest()
            var predicates: [NSPredicate] = []
            if let owner {
                predicates.append(NSPredicate(format: "owner_ = %@", owner.uppercased()))
            }
            if !prefix.isEmpty {
                predicates.append(NSPredicate(format: "name_ BEGINSWITH[c] %@", prefix.uppercased()))
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
            request.fetchLimit = limit
            do {
                let rows = try ctx.fetch(request)
                return rows.map { row in
                    ObjectSuggestion(
                        owner: row.owner_ ?? "",
                        name: row.name_ ?? "",
                        type: row.type_ ?? "")
                }
            } catch {
                self.logger.error("objects fetch failed: \(error.localizedDescription, privacy: .public)")
                return []
            }
        }
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
