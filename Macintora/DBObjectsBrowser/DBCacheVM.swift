import Foundation
import SwiftUI
import Combine
import CoreData
import os
import OracleNIO
import NIOCore
import Logging
import ServiceLifecycle

extension os.Logger {
    var cache: os.Logger { os.Logger(subsystem: os.Logger.subsystem, category: "cache") }
}

public enum OracleObjectType: String, CaseIterable, CustomStringConvertible, Sendable {
    public var description: String { self.rawValue }

    case table = "TABLE"
    case view = "VIEW"
    case type = "TYPE"
    case package = "PACKAGE"
    case index = "INDEX"
    case trigger = "TRIGGER"
    case procedure = "PROCEDURE"
    case function = "FUNCTION"
    case unknown = "UNKNOWN"
}

struct OracleObject: CustomStringConvertible, Sendable {
    let owner: String
    let name: String
    let type: OracleObjectType
    let lastDDL: Date
    let createDate: Date
    let editionName: String?
    let isEditionable: Bool
    let isValid: Bool
    let objectId: Int

    var description: String {
        "owner: \(owner), name: \(name), type: \(type), createDate: \(createDate.ISO8601Format()), lastDDL: \(lastDDL.ISO8601Format()), objectID: \(objectId), isValid: \(isValid), isEditionable: \(isEditionable), editionName: \(editionName ?? "")"
    }
}

actor ObjectQueue {
    private var queue = Queue<OracleObject>()

    func enqueue(_ obj: OracleObject) {
        queue.enqueue(obj)
    }

    func enqueue(_ objs: [OracleObject]) {
        queue.enqueue(objs)
    }

    func dequeue() -> OracleObject? {
        queue.dequeue()
    }

    var length: Int { queue.count }
}

actor CacheState {
    private(set) var isCacheEnqueueing = false
    private(set) var activeSessions = 0

    func startEnqueuing() { isCacheEnqueueing = true }
    func stopEnqueuing() { isCacheEnqueueing = false }
    func startSession() { activeSessions += 1 }
    func completeSession() { activeSessions -= 1 }
}

// MARK: - DTOs (data fetched from DB before CoreData writes)

struct TableDTO: Sendable {
    let owner: String
    let name: String
    let numRows: Int
    let lastAnalyzed: Date?
    let isPartitioned: Bool
    let sqltext: String?
    let isEditioning: Bool
    let isReadOnly: Bool
    let columns: [TableColumnDTO]
}

struct TableColumnDTO: Sendable {
    let owner: String
    let tableName: String
    let columnName: String
    let dataType: String
    let dataPrecision: Int?
    let dataScale: Int?
    let dataLength: Int
    let isNullable: Bool
    let columnID: Int?
    let dataDefault: String?
    let numDistinct: Int
    let isIdentity: Bool
    let numNulls: Int
    let isHidden: Bool
    let isVirtual: Bool
    let isUserGenerated: Bool
    let internalColumnID: Int
}

struct IndexDTO: Sendable {
    let owner: String
    let name: String
    let type: String
    let tableOwner: String
    let tableName: String
    let tablespaceName: String?
    let isUnique: Bool
    let leafBlocks: Int
    let distinctKeys: Int
    let avgLeafBlocksPerKey: Double
    let avgDataBlocksPerKey: Double
    let clusteringFactor: Int
    let isValid: Bool
    let numRows: Int
    let sampleSize: Int
    let lastAnalyzed: Date?
    let degree: String?
    let isPartitioned: Bool
    let isVisible: Bool
    let columns: [IndexColumnDTO]
}

struct IndexColumnDTO: Sendable {
    let owner: String
    let indexName: String
    let columnName: String
    let columnPosition: Int
    let columnLength: Int
    let isDescending: Bool
}

struct TriggerDTO: Sendable {
    let owner: String
    let name: String
    let type: String
    let event: String
    let tableOwner: String?
    let baseObjectType: String
    let tableName: String?
    let columnName: String?
    let referencingNames: String
    let whenClause: String?
    let isEnabled: Bool
    let description: String?
    let actionType: String
    let body: String?
    let isCrossEdition: Bool
    let isBeforeStatement: Bool
    let isBeforeRow: Bool
    let isAfterStatement: Bool
    let isAfterRow: Bool
    let isInsteadOfRow: Bool
    let isFireOnce: Bool
}

struct SourceRowDTO: Sendable {
    let type: String
    let owner: String
    let name: String
    let text: String
}

// MARK: - Row access helpers

extension OracleRandomAccessRow {
    func optString(_ column: String) -> String? {
        guard self.contains(column) else { return nil }
        return try? self[column].decode(String.self)
    }
    func optInt(_ column: String) -> Int? {
        guard self.contains(column) else { return nil }
        return try? self[column].decode(Int.self)
    }
    func optDouble(_ column: String) -> Double? {
        guard self.contains(column) else { return nil }
        return try? self[column].decode(Double.self)
    }
    func optDate(_ column: String) -> Date? {
        guard self.contains(column) else { return nil }
        return try? self[column].decode(Date.self)
    }
}

// MARK: - DBCacheVM

@MainActor
final class DBCacheVM: nonisolated ObservableObject {
    @Published var isConnected = ConnectionStatus.disconnected
    @Published var dbVersionFull: String?
    @Published var lastUpdate: Date?
    @Published var persistenceController: PersistenceController
    @Published var isReloading = false

    @AppStorage("cacheUpdatePrefetchSize") private var cacheUpdatePrefetchSize: Int = 10000
    @AppStorage("cacheUpdateBatchSize") private var cacheUpdateBatchSize: Int = 200
    @AppStorage("includeSystemObjects") private var includeSystemObjects = false
    @AppStorage("cacheUpdateSessionLimit") private var cacheUpdateSessionLimit: Int = 5
    @AppStorage("searchLimit") var searchLimit: Int = 20

    let connDetails: ConnectionDetails
    private var client: OracleClient?
    private var clientRunTask: Task<Void, Never>?
    private var objectQueues: [OracleObjectType: ObjectQueue] = [:]
    var dbVersionMajor: Int?
    let dateFormatter: DateFormatter = DateFormatter()
    var cacheState = CacheState()
    @Published var searchCriteria: DBCacheSearchCriteria

    private let oracleLogger: Logging.Logger = {
        var logger = Logging.Logger(label: "com.iliasazonov.macintora.oracle.cache")
        logger.logLevel = .notice
        return logger
    }()

    var lastUpdatedStr: String {
        guard let lst = lastUpdate else { return "(never)" }
        dateFormatter.calendar = Calendar(identifier: .iso8601)
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return dateFormatter.string(from: lst)
    }

    init(connDetails: ConnectionDetails, selectedObjectName: String? = nil) {
        self.connDetails = connDetails
        self.searchCriteria = DBCacheSearchCriteria(for: connDetails.tns)
        persistenceController = PersistenceController(name: connDetails.tns)
        setConnDetailsFromCache()
        OracleObjectType.allCases.forEach { objectQueues[$0] = ObjectQueue() }
        if let selected = selectedObjectName {
            searchCriteria.searchText = selected
        }
    }

    init(preview: Bool = true) {
        self.connDetails = ConnectionDetails(username: "user", password: "password", tns: "preview", connectionRole: .regular)
        self.searchCriteria = DBCacheSearchCriteria(for: connDetails.tns)
        persistenceController = PersistenceController.preview
        OracleObjectType.allCases.forEach { objectQueues[$0] = ObjectQueue() }
    }

    func setConnDetailsFromCache() {
        let context = persistenceController.container.newBackgroundContext()
        let request = ConnDatabase.fetchRequest(tns: connDetails.tns)
        let dbs = (try? context.fetch(request)) ?? []
        if let db = dbs.first {
            let lastUpdate = db.lastUpdate
            let dbVerFull = db.versionFull
            Task { @MainActor [self] in
                self.lastUpdate = lastUpdate
                self.dbVersionFull = dbVerFull
            }
        }
    }

    func clearCache() {
        Task(priority: .utility) {
            do {
                try await deleteAll(from: "DBCacheTableColumn")
                try await deleteAll(from: "DBCacheTable")
                try await deleteAll(from: "DBCacheIndexColumn")
                try await deleteAll(from: "DBCacheIndex")
                try await deleteAll(from: "DBCacheSource")
                try await deleteAll(from: "DBCacheObject")
                try await deleteAll(from: "DBCacheTrigger")
            } catch {
                log.cache.error("\(error.localizedDescription, privacy: .public)")
            }
            await setLastUpdateAsync(nil)
            self.persistenceController.container.viewContext.refreshAllObjects()
        }
    }

    // MARK: - Update cache

    func updateCache(ignoreLastUpdate: Bool = false, withCleanup: Bool = false, cleanupOnly: Bool = false) {
        isReloading = true
        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            if self.isConnected == .disconnected {
                do {
                    try await self.connectSvc()
                    await MainActor.run { self.isConnected = .connected }
                    await self.updateConnDatabase()
                } catch {
                    log.cache.error("could not connect to the database: \(error.localizedDescription, privacy: .public)")
                    await MainActor.run { self.isConnected = .disconnected }
                    return
                }
            }
            if withCleanup || cleanupOnly {
                await self.cleanupDroppedObjects()
            }
            if !cleanupOnly {
                await withTaskGroup(of: Void.self) { taskGroup in
                    await self.cacheState.startEnqueuing()
                    taskGroup.addTask { @concurrent in await self.populateObjectQueues(ignoreLastUpdate: ignoreLastUpdate) }
                    taskGroup.addTask { @concurrent in await self.processObjectQueues() }
                }
            }
            await self.disconnectSvc()
            await MainActor.run {
                self.isConnected = .disconnected
                self.isReloading = false
            }
        }
    }

    // MARK: - Service connection

    var store: ConnectionStore?
    var keychain: KeychainService = KeychainService()

    func connectSvc() async throws {
        log.cache.debug("Attempting to create an OracleClient")
        if self.isConnected == .connected { return }
        guard let store else {
            log.cache.error("DBCacheVM: ConnectionStore not configured before connect")
            throw OracleEndpoint.ResolveError.unknownConnection
        }
        let config = try OracleEndpoint.configuration(for: connDetails, store: store, keychain: keychain)
        var options = OracleClient.Options()
        options.maximumConnections = cacheUpdateSessionLimit
        options.minimumConnections = 0
        let newClient = OracleClient(
            configuration: config,
            options: options,
            drcp: false,
            eventLoopGroup: OracleEventLoopGroup.shared,
            backgroundLogger: oracleLogger
        )
        self.client = newClient
        self.clientRunTask = Task {
            await newClient.run()
        }
        log.cache.debug("OracleClient created")
    }

    func disconnectSvc() async {
        // OracleClient has no explicit close — cancel the run task to shut it down.
        clientRunTask?.cancel()
        await clientRunTask?.value
        client = nil
        clientRunTask = nil
        isConnected = .disconnected
    }

    /// Runs the closure on a new CoreData background context.
    ///
    /// Bypasses the `NSPersistentContainer.performBackgroundTask` API, which has a
    /// non-Sendable closure signature in the SDK headers and refuses to compile
    /// under Swift 6 strict concurrency. Instead we spin up a fresh background
    /// context and execute via `context.perform(_:)`, which is Sendable-clean.
    private func backgroundPerform(_ body: @escaping @Sendable (NSManagedObjectContext) -> Void) async {
        let context = persistenceController.container.newBackgroundContext()
        await context.perform {
            body(context)
        }
    }

    private func backgroundPerformThrowing(_ body: @escaping @Sendable (NSManagedObjectContext) throws -> Void) async throws {
        let context = persistenceController.container.newBackgroundContext()
        try await context.perform {
            try body(context)
        }
    }

    private func withClient<T: Sendable>(
        _ body: @concurrent (inout sending OracleClient.PooledConnection) async throws -> sending T
    ) async throws -> T {
        guard let client else { throw AppDBError(kind: .connection, message: "No database client available") }
        return try await client.withConnection { conn in
            try await body(&conn)
        }
    }

    // MARK: - Object discovery

    func buildCleanupCheckQuery(for ids: String) -> String {
        """
        with rws as (select '\(ids)' str from dual)
        , ids as (select regexp_substr (str,'[^,]+', 1, level) id
        from rws connect by level <= length ( str ) - length ( replace ( str, ',' ) ) + 1
        )
        select to_number(ids.id) object_id
        from ids
        where not exists (select 1 from dba_objects o where o.object_id = ids.id)
        """
    }

    func buildObjectQuerySQL(ignoreLastUpdate: Bool = false) -> String {
        var sql = """
select /*+ rule */ owner, object_name, object_type, object_id, created, editionable, edition_name, status
, greatest(last_ddl_time
, nvl(( select last_ddl_time from dba_objects o1 where o1.owner = o.owner and o1.object_name = o.object_name and o1.object_type = o.object_type || ' BODY'), o.last_ddl_time)) as last_ddl_time
from dba_objects o
"""
        sql += " where object_type in ("
        sql += OracleObjectType.allCases.map { "'\($0.rawValue)'" }.joined(separator: ",")
        sql += ") "
        if !searchCriteria.ownerInclusionList.isEmpty {
            sql += " and owner in ("
            sql += searchCriteria.ownerInclusionList.map { "'\($0)'" }.joined(separator: ",")
            sql += ")"
        }
        if !includeSystemObjects {
            sql += " and owner NOT in (select username from dba_users where oracle_maintained = 'Y')"
        }
        if !searchCriteria.namePrefixInclusionList.isEmpty {
            sql += " and ( "
            sql += searchCriteria.namePrefixInclusionList.map { "object_name like '\($0.replacing("_", with: #"\_"#))%' escape \(#"'\'"#)" }.joined(separator: " or ")
            sql += ")"
        }
        sql += " and object_name not like 'SYS_IL%'"
        if let lstDate = self.lastUpdate, !ignoreLastUpdate {
            dateFormatter.calendar = Calendar(identifier: .iso8601)
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let lstString = dateFormatter.string(from: lstDate)
            sql += " and ( last_ddl_time > to_date('\(lstString)', 'yyyy-mm-dd hh24:mi:ss') or"
            sql += " exists (select 1 from dba_objects o1 where o1.owner = o.owner and o1.object_name = o.object_name and o1.object_type = o.object_type || ' BODY'"
            sql += " and o1.last_ddl_time > to_date('\(lstString)', 'yyyy-mm-dd hh24:mi:ss') ) )"
        }
        return sql
    }

    func populateObjectQueues(ignoreLastUpdate: Bool = false) async {
        if await MainActor.run(body: { self.isConnected }) != .connected {
            log.cache.error("Not connected to Oracle database")
            return
        }
        let sql = buildObjectQuerySQL(ignoreLastUpdate: ignoreLastUpdate)
        await cacheState.startSession()
        do {
            try await withClient { [cacheUpdatePrefetchSize, oracleLogger, objectQueues] conn in
                var options = StatementOptions()
                options.prefetchRows = cacheUpdatePrefetchSize
                options.arraySize = max(cacheUpdatePrefetchSize, 100)
                let stream = try await conn.execute(
                    OracleStatement(stringLiteral: sql),
                    options: options,
                    logger: oracleLogger
                )
                for try await row in stream {
                    let rr = row.makeRandomAccess()
                    guard let owner = rr.optString("OWNER"),
                          let name = rr.optString("OBJECT_NAME"),
                          let typeStr = rr.optString("OBJECT_TYPE"),
                          let objectId = rr.optInt("OBJECT_ID") else { continue }
                    let obj = OracleObject(
                        owner: owner,
                        name: name,
                        type: OracleObjectType(rawValue: typeStr) ?? .unknown,
                        lastDDL: rr.optDate("LAST_DDL_TIME") ?? Date(),
                        createDate: rr.optDate("CREATED") ?? Date(),
                        editionName: rr.optString("EDITION_NAME"),
                        isEditionable: rr.optString("EDITIONABLE") == "Y",
                        isValid: rr.optString("STATUS") == "VALID",
                        objectId: objectId
                    )
                    await objectQueues[obj.type]?.enqueue(obj)
                }
            }
        } catch {
            log.cache.error("populateObjectQueues failed: \(error.localizedDescription, privacy: .public)")
        }
        await cacheState.stopEnqueuing()
        await cacheState.completeSession()
    }

    // MARK: - Queue processing

    func processObjectQueues() async {
        let updateDate = Date.now
        await withTaskGroup(of: Void.self) { taskGroup in
            for (key, _) in objectQueues {
                taskGroup.addTask { @concurrent in
                    await self.processObjectQueue(for: key)
                }
            }
        }
        await setLastUpdateAsync(updateDate)
    }

    func processObjectQueue(for objectType: OracleObjectType) async {
        let q = self.objectQueues[objectType]!
        var objs = [OracleObject]()
        var iter = 0
        repeat {
            while let obj = await q.dequeue() {
                objs.append(obj)
                iter += 1
                if iter % cacheUpdateBatchSize == 0 {
                    while await cacheState.activeSessions >= cacheUpdateSessionLimit {
                        await Task.yield()
                        try? await Task.sleep(for: .seconds(3))
                    }
                    let objstemp = objs
                    await cacheState.startSession()
                    if objectType == .package || objectType == .type || objectType == .procedure || objectType == .function {
                        await self.processSourceChunk(objstemp)
                    } else {
                        await self.processChunkOfObjects(objstemp, objectType: objectType)
                    }
                    await cacheState.completeSession()
                    objs.removeAll()
                }
            }
            if !objs.isEmpty {
                while await cacheState.activeSessions >= cacheUpdateSessionLimit {
                    await Task.yield()
                    try? await Task.sleep(for: .seconds(3))
                }
                let objstemp = objs
                await cacheState.startSession()
                if objectType == .package || objectType == .type || objectType == .procedure || objectType == .function {
                    await self.processSourceChunk(objstemp)
                } else {
                    await self.processChunkOfObjects(objstemp, objectType: objectType)
                }
                await cacheState.completeSession()
                objs.removeAll()
            }
            if !(await cacheState.isCacheEnqueueing) {
                break
            } else {
                try? await Task.sleep(for: .seconds(3))
            }
        } while true
    }

    func processChunkOfObjects(_ objs: [OracleObject], objectType: OracleObjectType) async {
        switch objectType {
        case .table, .view:
            let tables = (try? await fetchTables(objs, isView: objectType == .view)) ?? []
            await persistTables(tables, isView: objectType == .view, objs: objs)
        case .index:
            let indexes = (try? await fetchIndexes(objs)) ?? []
            await persistIndexes(indexes, objs: objs)
        case .trigger:
            let triggers = (try? await fetchTriggers(objs)) ?? []
            await persistTriggers(triggers, objs: objs)
        default:
            break
        }
    }

    // MARK: - Tables

    private func fetchTables(_ objs: [OracleObject], isView: Bool) async throws -> [TableDTO] {
        guard !objs.isEmpty else { return [] }
        var sql: String
        if isView {
            sql = "select owner, view_name table_name, 0 num_rows, null last_analyzed, 'NO' partitioned, editioning_view, read_only, text from dba_views where (owner, view_name) in ("
        } else {
            sql = "select owner, table_name, num_rows, last_analyzed, partitioned, 'N' editioning_view, 'N' read_only, null text from dba_tables where (owner, table_name) in ("
        }
        var bindings = OracleBindings()
        var placeholders: [String] = []
        for (i, obj) in objs.enumerated() {
            placeholders.append("(:o\(i), :n\(i))")
            bindings.append(obj.owner, context: .default, bindName: "o\(i)")
            bindings.append(obj.name, context: .default, bindName: "n\(i)")
        }
        sql += placeholders.joined(separator: ",")
        sql += ")"

        let logger = oracleLogger
        let finalSQL = sql
        let finalBindings = bindings
        return try await withClient { conn in
            var options = StatementOptions()
            options.prefetchRows = 1000
            options.arraySize = 1000
            let stream = try await conn.execute(
                OracleStatement(unsafeSQL: finalSQL, binds: finalBindings),
                options: options,
                logger: logger
            )
            // Drain the parent stream first. Issuing another execute on the
            // same PooledConnection while a stream is open misaligns the
            // oracle-nio protocol parser and crashes deep in QueryParameter.
            var pending: [TableDTO] = []
            for try await row in stream {
                let rr = row.makeRandomAccess()
                guard let owner = rr.optString("OWNER"),
                      let name = rr.optString("TABLE_NAME") else { continue }
                pending.append(TableDTO(
                    owner: owner,
                    name: name,
                    numRows: rr.optInt("NUM_ROWS") ?? 0,
                    lastAnalyzed: rr.optDate("LAST_ANALYZED"),
                    isPartitioned: rr.optString("PARTITIONED") == "YES",
                    sqltext: rr.optString("TEXT"),
                    isEditioning: rr.optString("EDITIONING_VIEW") == "Y",
                    isReadOnly: rr.optString("READ_ONLY") == "Y",
                    columns: []
                ))
            }
            var tables: [TableDTO] = []
            tables.reserveCapacity(pending.count)
            for t in pending {
                let columns = (try? await Self.fetchTableColumns(on: &conn, owner: t.owner, table: t.name, logger: logger)) ?? []
                tables.append(TableDTO(
                    owner: t.owner,
                    name: t.name,
                    numRows: t.numRows,
                    lastAnalyzed: t.lastAnalyzed,
                    isPartitioned: t.isPartitioned,
                    sqltext: t.sqltext,
                    isEditioning: t.isEditioning,
                    isReadOnly: t.isReadOnly,
                    columns: columns
                ))
            }
            return tables
        }
    }

    private static func fetchTableColumns(on conn: inout sending OracleClient.PooledConnection, owner: String, table: String, logger: Logging.Logger) async throws -> [TableColumnDTO] {
        let statement: OracleStatement = """
            select owner, table_name, column_name, data_type, data_precision, data_scale, data_length, nullable, column_id, data_default, num_distinct, identity_column, num_nulls, hidden_column, virtual_column, user_generated, internal_column_id from dba_tab_cols where owner = \(owner) and table_name = \(table)
            """
        let stream = try await conn.execute(statement, logger: logger)
        var cols: [TableColumnDTO] = []
        for try await row in stream {
            let rr = row.makeRandomAccess()
            guard let columnName = rr.optString("COLUMN_NAME"),
                  let dataType = rr.optString("DATA_TYPE") else { continue }
            cols.append(TableColumnDTO(
                owner: owner,
                tableName: table,
                columnName: columnName,
                dataType: dataType,
                dataPrecision: rr.optInt("DATA_PRECISION"),
                dataScale: rr.optInt("DATA_SCALE"),
                dataLength: rr.optInt("DATA_LENGTH") ?? 0,
                isNullable: rr.optString("NULLABLE") == "Y",
                columnID: rr.optInt("COLUMN_ID"),
                dataDefault: rr.optString("DATA_DEFAULT"),
                numDistinct: rr.optInt("NUM_DISTINCT") ?? 0,
                isIdentity: rr.optString("IDENTITY_COLUMN") == "YES",
                numNulls: rr.optInt("NUM_NULLS") ?? 0,
                isHidden: rr.optString("HIDDEN_COLUMN") == "YES",
                isVirtual: rr.optString("VIRTUAL_COLUMN") == "YES",
                isUserGenerated: rr.optString("USER_GENERATED") == "YES",
                internalColumnID: rr.optInt("INTERNAL_COLUMN_ID") ?? 0
            ))
        }
        return cols
    }

    private func persistTables(_ tables: [TableDTO], isView: Bool, objs: [OracleObject]) async {
        await self.backgroundPerform { context in
            let request = DBCacheTable.fetchRequest()
            for table in tables {
                request.predicate = NSPredicate(format: "name_ = %@ and owner_ = %@", table.name, table.owner)
                let results = (try? context.fetch(request)) ?? []
                let obj = results.first ?? DBCacheTable(context: context)
                obj.isView = isView
                obj.owner_ = table.owner
                obj.name_ = table.name
                obj.numRows = Int64(table.numRows)
                obj.lastAnalyzed = table.lastAnalyzed
                obj.isPartitioned = table.isPartitioned
                obj.isEditioning = table.isEditioning
                obj.isReadOnly = table.isReadOnly
                if isView {
                    obj.sqltext = "create or replace\(table.isEditioning ? " editioning" : "") view \(table.owner).\(table.name) as ".appending(table.sqltext ?? "")
                }
                try? self.deleteTableColumns(for: obj, in: context)
                for col in table.columns {
                    let entity = DBCacheTableColumn(context: context)
                    entity.isNullable = col.isNullable
                    entity.dataType_ = col.dataType
                    entity.columnID = col.columnID.map { NSNumber(value: $0) }
                    entity.internalColumnID = Int16(col.internalColumnID)
                    entity.columnName_ = col.columnName
                    entity.length = Int32(col.dataLength)
                    entity.defaultValue = col.dataDefault
                    entity.isIdentity = col.isIdentity
                    entity.isHidden = col.isHidden
                    entity.isVirtual = col.isVirtual
                    entity.isSysGen = !col.isUserGenerated
                    entity.numNulls = Int64(col.numNulls)
                    entity.numDistinct = Int64(col.numDistinct)
                    entity.precision = col.dataPrecision.map { NSNumber(value: $0) }
                    entity.scale = col.dataScale.map { NSNumber(value: $0) }
                    entity.owner_ = col.owner
                    entity.tableName_ = col.tableName
                }
            }
            self.processObjects(objs, context: context)
            try? context.save()
        }
    }

    // MARK: - Indexes

    private func fetchIndexes(_ objs: [OracleObject]) async throws -> [IndexDTO] {
        guard !objs.isEmpty else { return [] }
        var sql = "select owner, index_name, index_type, table_owner, table_name, tablespace_name, uniqueness, leaf_blocks, distinct_keys, avg_leaf_blocks_per_key, avg_data_blocks_per_key, clustering_factor, status, num_rows, sample_size, last_analyzed, degree, partitioned, visibility from dba_indexes where index_type != 'LOB' and (owner, index_name) in ("
        var bindings = OracleBindings()
        var placeholders: [String] = []
        for (i, obj) in objs.enumerated() {
            placeholders.append("(:o\(i), :n\(i))")
            bindings.append(obj.owner, context: .default, bindName: "o\(i)")
            bindings.append(obj.name, context: .default, bindName: "n\(i)")
        }
        sql += placeholders.joined(separator: ",")
        sql += ")"

        let logger = oracleLogger
        let finalSQL = sql
        let finalBindings = bindings
        return try await withClient { conn in
            var options = StatementOptions()
            options.prefetchRows = 1000
            let stream = try await conn.execute(
                OracleStatement(unsafeSQL: finalSQL, binds: finalBindings),
                options: options,
                logger: logger
            )
            // Drain the parent stream before issuing per-index column queries.
            // Nested execute on the same PooledConnection while a stream is
            // open misaligns the oracle-nio protocol parser and crashes deep
            // in QueryParameter.decode.
            var pending: [IndexDTO] = []
            for try await row in stream {
                let rr = row.makeRandomAccess()
                guard let owner = rr.optString("OWNER"),
                      let name = rr.optString("INDEX_NAME") else { continue }
                pending.append(IndexDTO(
                    owner: owner,
                    name: name,
                    type: rr.optString("INDEX_TYPE") ?? "",
                    tableOwner: rr.optString("TABLE_OWNER") ?? "",
                    tableName: rr.optString("TABLE_NAME") ?? "",
                    tablespaceName: rr.optString("TABLESPACE_NAME"),
                    isUnique: rr.optString("UNIQUENESS") == "UNIQUE",
                    leafBlocks: rr.optInt("LEAF_BLOCKS") ?? 0,
                    distinctKeys: rr.optInt("DISTINCT_KEYS") ?? 0,
                    avgLeafBlocksPerKey: rr.optDouble("AVG_LEAF_BLOCKS_PER_KEY") ?? 0,
                    avgDataBlocksPerKey: rr.optDouble("AVG_DATA_BLOCKS_PER_KEY") ?? 0,
                    clusteringFactor: rr.optInt("CLUSTERING_FACTOR") ?? 0,
                    isValid: rr.optString("STATUS") == "VALID",
                    numRows: rr.optInt("NUM_ROWS") ?? 0,
                    sampleSize: rr.optInt("SAMPLE_SIZE") ?? 0,
                    lastAnalyzed: rr.optDate("LAST_ANALYZED"),
                    degree: rr.optString("DEGREE"),
                    isPartitioned: rr.optString("PARTITIONED") == "YES",
                    isVisible: rr.optString("VISIBILITY") == "VISIBLE",
                    columns: []
                ))
            }
            var indexes: [IndexDTO] = []
            indexes.reserveCapacity(pending.count)
            for idx in pending {
                let columns = (try? await Self.fetchIndexColumns(on: &conn, owner: idx.owner, index: idx.name, logger: logger)) ?? []
                indexes.append(IndexDTO(
                    owner: idx.owner,
                    name: idx.name,
                    type: idx.type,
                    tableOwner: idx.tableOwner,
                    tableName: idx.tableName,
                    tablespaceName: idx.tablespaceName,
                    isUnique: idx.isUnique,
                    leafBlocks: idx.leafBlocks,
                    distinctKeys: idx.distinctKeys,
                    avgLeafBlocksPerKey: idx.avgLeafBlocksPerKey,
                    avgDataBlocksPerKey: idx.avgDataBlocksPerKey,
                    clusteringFactor: idx.clusteringFactor,
                    isValid: idx.isValid,
                    numRows: idx.numRows,
                    sampleSize: idx.sampleSize,
                    lastAnalyzed: idx.lastAnalyzed,
                    degree: idx.degree,
                    isPartitioned: idx.isPartitioned,
                    isVisible: idx.isVisible,
                    columns: columns
                ))
            }
            return indexes
        }
    }

    private static func fetchIndexColumns(on conn: inout sending OracleClient.PooledConnection, owner: String, index: String, logger: Logging.Logger) async throws -> [IndexColumnDTO] {
        let statement: OracleStatement = """
            select index_owner, index_name, column_name, column_position, column_length, descend from dba_ind_columns where index_owner = \(owner) and index_name = \(index)
            """
        let stream = try await conn.execute(statement, logger: logger)
        var cols: [IndexColumnDTO] = []
        for try await row in stream {
            let rr = row.makeRandomAccess()
            guard let columnName = rr.optString("COLUMN_NAME") else { continue }
            cols.append(IndexColumnDTO(
                owner: owner,
                indexName: index,
                columnName: columnName,
                columnPosition: rr.optInt("COLUMN_POSITION") ?? 0,
                columnLength: rr.optInt("COLUMN_LENGTH") ?? 0,
                isDescending: rr.optString("DESCEND") == "DESC"
            ))
        }
        return cols
    }

    private func persistIndexes(_ indexes: [IndexDTO], objs: [OracleObject]) async {
        await self.backgroundPerform { context in
            let request = DBCacheIndex.fetchRequest()
            for idx in indexes {
                request.predicate = NSPredicate(format: "name_ = %@ and owner_ = %@", idx.name, idx.owner)
                let results = (try? context.fetch(request)) ?? []
                let obj = results.first ?? DBCacheIndex(context: context)
                obj.owner_ = idx.owner
                obj.name_ = idx.name
                obj.type_ = idx.type
                obj.tableOwner = idx.tableOwner
                obj.tableName = idx.tableName
                obj.tablespaceName_ = idx.tablespaceName
                obj.isUnique = idx.isUnique
                obj.leafBlocks = Int64(idx.leafBlocks)
                obj.distinctKeys = Int64(idx.distinctKeys)
                obj.avgLeafBlocksPerKey = idx.avgLeafBlocksPerKey
                obj.avgDataBlocksPerKey = idx.avgDataBlocksPerKey
                obj.clusteringFactor = Int64(idx.clusteringFactor)
                obj.isValid = idx.isValid
                obj.numRows = Int64(idx.numRows)
                obj.sampleSize = Int64(idx.sampleSize)
                obj.lastAnalyzed = idx.lastAnalyzed
                obj.degree_ = idx.degree
                obj.isPartitioned = idx.isPartitioned
                obj.isVisible = idx.isVisible
                try? self.deleteIndexColumns(for: obj, in: context)
                for col in idx.columns {
                    let entity = DBCacheIndexColumn(context: context)
                    entity.isDescending = col.isDescending
                    entity.position = Int16(col.columnPosition)
                    entity.columnName_ = col.columnName
                    entity.length = Int32(col.columnLength)
                    entity.owner_ = col.owner
                    entity.indexName_ = col.indexName
                }
            }
            self.processObjects(objs, context: context)
            try? context.save()
        }
    }

    // MARK: - Triggers

    private func fetchTriggers(_ objs: [OracleObject]) async throws -> [TriggerDTO] {
        guard !objs.isEmpty, objs.count < 1000 else { return [] }
        var sql = "select owner, trigger_name, trigger_type, triggering_event, table_owner, base_object_type, table_name, column_name, referencing_names, when_clause, status, description, action_type, trigger_body, crossedition, before_statement, before_row, after_row, after_statement, instead_of_row, fire_once from dba_triggers where owner in ($OWNERS$) and trigger_name in ($NAMES$)"
        var bindings = OracleBindings()
        let owners = objs.map { $0.owner }.unique()
        let names = objs.map { $0.name }.unique()
        var ownerPlaceholders: [String] = []
        for (i, v) in owners.enumerated() {
            ownerPlaceholders.append(":o\(i)")
            bindings.append(v, context: .default, bindName: "o\(i)")
        }
        var namePlaceholders: [String] = []
        for (i, v) in names.enumerated() {
            namePlaceholders.append(":n\(i)")
            bindings.append(v, context: .default, bindName: "n\(i)")
        }
        sql = sql.replacing("$OWNERS$", with: ownerPlaceholders.joined(separator: ","))
        sql = sql.replacing("$NAMES$", with: namePlaceholders.joined(separator: ","))

        let logger = oracleLogger
        let finalSQL = sql
        let finalBindings = bindings
        return try await withClient { conn in
            var options = StatementOptions()
            options.prefetchRows = 5000
            let stream = try await conn.execute(
                OracleStatement(unsafeSQL: finalSQL, binds: finalBindings),
                options: options,
                logger: logger
            )
            var triggers: [TriggerDTO] = []
            for try await row in stream {
                let rr = row.makeRandomAccess()
                guard let owner = rr.optString("OWNER"), let name = rr.optString("TRIGGER_NAME") else { continue }
                triggers.append(TriggerDTO(
                    owner: owner,
                    name: name,
                    type: rr.optString("TRIGGER_TYPE") ?? "",
                    event: rr.optString("TRIGGERING_EVENT") ?? "",
                    tableOwner: rr.optString("TABLE_OWNER"),
                    baseObjectType: rr.optString("BASE_OBJECT_TYPE") ?? "",
                    tableName: rr.optString("TABLE_NAME"),
                    columnName: rr.optString("COLUMN_NAME"),
                    referencingNames: rr.optString("REFERENCING_NAMES") ?? "",
                    whenClause: rr.optString("WHEN_CLAUSE"),
                    isEnabled: rr.optString("STATUS") == "ENABLED",
                    description: rr.optString("DESCRIPTION"),
                    actionType: rr.optString("ACTION_TYPE") ?? "",
                    body: rr.optString("TRIGGER_BODY"),
                    isCrossEdition: rr.optString("CROSSEDITION") == "YES",
                    isBeforeStatement: rr.optString("BEFORE_STATEMENT") == "YES",
                    isBeforeRow: rr.optString("BEFORE_ROW") == "YES",
                    isAfterStatement: rr.optString("AFTER_STATEMENT") == "YES",
                    isAfterRow: rr.optString("AFTER_ROW") == "YES",
                    isInsteadOfRow: rr.optString("INSTEAD_OF_ROW") == "YES",
                    isFireOnce: rr.optString("FIRE_ONCE") == "YES"
                ))
            }
            return triggers
        }
    }

    private func persistTriggers(_ triggers: [TriggerDTO], objs: [OracleObject]) async {
        await self.backgroundPerform { context in
            let request = DBCacheTrigger.fetchRequest()
            for t in triggers {
                request.predicate = NSPredicate(format: "name_ = %@ and owner_ = %@", t.name, t.owner)
                let results = (try? context.fetch(request)) ?? []
                let obj = results.first ?? DBCacheTrigger(context: context)
                obj.owner = t.owner
                obj.name = t.name
                obj.type = t.type
                obj.event = t.event
                obj.objectOwner = t.tableOwner
                obj.objectType = t.baseObjectType
                obj.objectName = t.tableName
                obj.columnName = t.columnName
                obj.referencingNames = t.referencingNames
                obj.whenClause = t.whenClause
                obj.isEnabled = t.isEnabled
                obj.descr = t.description
                obj.actionType = t.actionType
                obj.body = t.body
                obj.isCrossEdition = t.isCrossEdition
                obj.isBeforeStatement = t.isBeforeStatement
                obj.isBeforeRow = t.isBeforeRow
                obj.isAfterStatement = t.isAfterStatement
                obj.isAfterRow = t.isAfterRow
                obj.isInsteadOfRow = t.isInsteadOfRow
                obj.isFireOnce = t.isFireOnce
            }
            self.processObjects(objs, context: context)
            try? context.save()
        }
    }

    // MARK: - Source

    private struct TempObj: Hashable {
        let owner: String, name: String
    }

    private struct TempSource {
        var textSpec: String?, textBody: String?
    }

    func processSourceChunk(_ objs: [OracleObject]) async {
        guard !objs.isEmpty, objs.count < 1000 else { return }
        let rows = (try? await fetchSourceRows(objs)) ?? []
        let tempObjs = buildSourceMap(from: rows)
        await updateSourceCache(tempObjs: tempObjs, objs: objs)
    }

    private func fetchSourceRows(_ objs: [OracleObject]) async throws -> [SourceRowDTO] {
        var sql = "select type, owner, name, text from dba_source where owner in ($OWNERS$) and name in ($NAMES$) and type in (:ts, :tb) order by type, owner, name, line"
        var bindings = OracleBindings()
        let owners = objs.map { $0.owner }.unique()
        let names = objs.map { $0.name }.unique()
        var ownerPlaceholders: [String] = []
        for (i, v) in owners.enumerated() {
            ownerPlaceholders.append(":o\(i)")
            bindings.append(v, context: .default, bindName: "o\(i)")
        }
        var namePlaceholders: [String] = []
        for (i, v) in names.enumerated() {
            namePlaceholders.append(":n\(i)")
            bindings.append(v, context: .default, bindName: "n\(i)")
        }
        let baseType = objs[0].type.rawValue
        bindings.append(baseType, context: .default, bindName: "ts")
        bindings.append(baseType + " BODY", context: .default, bindName: "tb")
        sql = sql.replacing("$OWNERS$", with: ownerPlaceholders.joined(separator: ","))
        sql = sql.replacing("$NAMES$", with: namePlaceholders.joined(separator: ","))

        let logger = oracleLogger
        let finalSQL = sql
        let finalBindings = bindings
        return try await withClient { conn in
            var options = StatementOptions()
            options.prefetchRows = 50_000
            let stream = try await conn.execute(
                OracleStatement(unsafeSQL: finalSQL, binds: finalBindings),
                options: options,
                logger: logger
            )
            var rows: [SourceRowDTO] = []
            for try await row in stream {
                let rr = row.makeRandomAccess()
                guard let type = rr.optString("TYPE"),
                      let owner = rr.optString("OWNER"),
                      let name = rr.optString("NAME") else { continue }
                rows.append(SourceRowDTO(type: type, owner: owner, name: name, text: rr.optString("TEXT") ?? ""))
            }
            return rows
        }
    }

    private func buildSourceMap(from rows: [SourceRowDTO]) -> [TempObj: TempSource] {
        var out: [TempObj: TempSource] = [:]
        guard !rows.isEmpty else { return out }
        var currentKey: (type: String, owner: String, name: String) = (rows[0].type, rows[0].owner, rows[0].name)
        var text = rows[0].text
        for row in rows.dropFirst() {
            let key = (row.type, row.owner, row.name)
            if key == currentKey {
                text.append(row.text)
            } else {
                commit(text: &text, key: currentKey, into: &out)
                currentKey = key
                text = row.text
            }
        }
        commit(text: &text, key: currentKey, into: &out)
        return out
    }

    private func commit(text: inout String, key: (type: String, owner: String, name: String), into map: inout [TempObj: TempSource]) {
        let withPrefix = "create or replace ".appending(text)
        let obj = TempObj(owner: key.owner, name: key.name)
        var entry = map[obj] ?? TempSource(textSpec: nil, textBody: nil)
        if key.type.contains("BODY") {
            entry.textBody = withPrefix
        } else {
            entry.textSpec = withPrefix
        }
        map[obj] = entry
        text.removeAll()
    }

    private func updateSourceCache(tempObjs: [TempObj: TempSource], objs: [OracleObject]) async {
        await self.backgroundPerform { context in
            let request = DBCacheSource.fetchRequest()
            for (key, value) in tempObjs {
                request.predicate = NSPredicate(format: "name_ = %@ and owner_ = %@", key.name, key.owner)
                let results = (try? context.fetch(request)) ?? []
                let cachedObj = results.first ?? DBCacheSource(context: context)
                cachedObj.name = key.name
                cachedObj.owner = key.owner
                cachedObj.textSpec = value.textSpec
                cachedObj.textBody = value.textBody
            }
            self.processObjects(objs, context: context)
            try? context.save()
        }
    }

    // MARK: - Cleanup dropped objects

    func cleanupDroppedObjects() async {
        // Collect IDs first, query DB, then drop.
        let idsByBatch: [String] = await MainActor.run {
            let context = self.persistenceController.container.newBackgroundContext()
            let request = DBCacheObject.fetchRequest()
            let results = (try? context.fetch(request)) ?? []
            var batches: [String] = []
            var batch = ""
            batch.reserveCapacity(4000)
            for r in results {
                if batch.lengthOfBytes(using: .utf8) > 3900 {
                    batch.append(contentsOf: String(r.objectId))
                    batches.append(batch)
                    batch.removeAll(keepingCapacity: true)
                } else {
                    batch.append(contentsOf: String(r.objectId))
                    batch.append(",")
                }
            }
            if !batch.isEmpty { batches.append(batch) }
            return batches
        }

        var idsToDrop: [Int] = []
        for idStr in idsByBatch {
            idsToDrop.append(contentsOf: await cleanupDroppedObjectsBatch(for: idStr))
        }
        guard !idsToDrop.isEmpty else { return }
        let finalIDs = idsToDrop
        await self.backgroundPerform { [self] context in
            let request = DBCacheObject.fetchRequest()
            request.predicate = NSPredicate(format: "objectId IN %@", finalIDs)
            let results = (try? context.fetch(request)) ?? []
            for r in results { self.dropLocalObject(r, with: context) }
            try? context.save()
        }
    }

    func cleanupDroppedObjectsBatch(for idStr: String) async -> [Int] {
        let sql = buildCleanupCheckQuery(for: idStr)
        let logger = oracleLogger
        do {
            return try await withClient { conn -> [Int] in
                let stream = try await conn.execute(OracleStatement(stringLiteral: sql), logger: logger)
                var collected: [Int] = []
                for try await row in stream {
                    if let id = try? row.makeRandomAccess()["OBJECT_ID"].decode(Int.self) {
                        collected.append(id)
                    }
                }
                return collected
            }
        } catch {
            log.cache.error("cleanup batch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - CoreData helpers

    nonisolated func processObjects(_ objs: [OracleObject], context: NSManagedObjectContext) {
        let request = DBCacheObject.fetchRequest()
        for obj in objs {
            request.predicate = NSPredicate(format: "name_ = %@ and owner_ = %@ and type_ = %@", obj.name, obj.owner, obj.type.rawValue)
            let results = (try? context.fetch(request)) ?? []
            let objCache = results.first ?? DBCacheObject(context: context)
            objCache.owner = obj.owner
            objCache.name = obj.name
            objCache.type = obj.type.rawValue
            objCache.lastDDLDate = obj.lastDDL
            objCache.createDate = obj.createDate
            objCache.editionName = obj.editionName
            objCache.isEditionable = obj.isEditionable
            objCache.isValid = obj.isValid
            objCache.objectId = obj.objectId
        }
    }

    nonisolated func deleteTableColumns(for table: DBCacheTable?, in context: NSManagedObjectContext) throws {
        guard let table else { return }
        let fetchRequest: NSFetchRequest<any NSFetchRequestResult> = NSFetchRequest(entityName: "DBCacheTableColumn")
        fetchRequest.predicate = NSPredicate(format: "owner_ = %@ and tableName_ = %@", table.owner, table.name)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        deleteRequest.resultType = .resultTypeObjectIDs
        let batchDelete = try context.execute(deleteRequest) as? NSBatchDeleteResult
        guard let deleteResult = batchDelete?.result else { return }
        let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: deleteResult as! [NSManagedObjectID]]
        if !changes.isEmpty {
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        }
    }

    nonisolated func deleteIndexColumns(for table: DBCacheIndex?, in context: NSManagedObjectContext) throws {
        guard let table else { return }
        let fetchRequest: NSFetchRequest<any NSFetchRequestResult> = NSFetchRequest(entityName: "DBCacheIndexColumn")
        fetchRequest.predicate = NSPredicate(format: "owner_ = %@ and indexName_ = %@", table.owner, table.name)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        deleteRequest.resultType = .resultTypeObjectIDs
        let batchDelete = try context.execute(deleteRequest) as? NSBatchDeleteResult
        guard let deleteResult = batchDelete?.result else { return }
        let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: deleteResult as! [NSManagedObjectID]]
        if !changes.isEmpty {
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        }
    }

    func refreshObject(_ currentObj: OracleObject) async {
        let sql: OracleStatement = """
            select /*+ rule */ owner, object_name, object_type, object_id, created, editionable, edition_name, status
            , greatest(last_ddl_time
            , nvl(( select last_ddl_time from dba_objects o1 where o1.owner = o.owner and o1.object_name = o.object_name and o1.object_type = o.object_type || ' BODY'), o.last_ddl_time)) as last_ddl_time
            from dba_objects o
            where object_type = \(currentObj.type.rawValue) and owner = \(currentObj.owner) and object_name = \(currentObj.name)
            """
        let logger = oracleLogger
        var fetchedObj: OracleObject?
        do {
            fetchedObj = try await withClient { conn -> OracleObject? in
                let stream = try await conn.execute(sql, logger: logger)
                for try await row in stream {
                    let rr = row.makeRandomAccess()
                    guard let owner = rr.optString("OWNER"),
                          let name = rr.optString("OBJECT_NAME"),
                          let typeStr = rr.optString("OBJECT_TYPE"),
                          let objectId = rr.optInt("OBJECT_ID") else { continue }
                    return OracleObject(
                        owner: owner,
                        name: name,
                        type: OracleObjectType(rawValue: typeStr) ?? .unknown,
                        lastDDL: rr.optDate("LAST_DDL_TIME") ?? Date(),
                        createDate: rr.optDate("CREATED") ?? Date(),
                        editionName: rr.optString("EDITION_NAME"),
                        isEditionable: rr.optString("EDITIONABLE") == "Y",
                        isValid: rr.optString("STATUS") == "VALID",
                        objectId: objectId
                    )
                }
                return nil
            }
        } catch {
            log.cache.error("refreshObject failed: \(error.localizedDescription, privacy: .public)")
        }
        if let obj = fetchedObj {
            if currentObj.type == .package || currentObj.type == .type {
                await self.processSourceChunk([obj])
            } else {
                await self.processChunkOfObjects([obj], objectType: obj.type)
            }
        } else {
            await dropLocalObject(currentObj)
        }
    }

    func dropLocalObject(_ obj: OracleObject) async {
        await self.backgroundPerform { context in
            let request = DBCacheObject.fetchRequest()
            request.predicate = NSPredicate(format: "name_ = %@ and owner_ = %@ and type_ = %@", obj.name, obj.owner, obj.type.rawValue)
            let results = (try? context.fetch(request)) ?? []
            if let objCache = results.first {
                context.delete(objCache)
                try? context.save()
            }
        }
    }

    nonisolated func dropLocalObject(_ obj: DBCacheObject, with context: NSManagedObjectContext) {
        switch OracleObjectType(rawValue: obj.type) {
        case .table, .view:
            let tableRequest = DBCacheTable.fetchRequest()
            tableRequest.predicate = NSPredicate(format: "name_ = %@ and owner_ = %@", obj.name, obj.owner)
            let table = (try? context.fetch(tableRequest))?.first
            try? deleteTableColumns(for: table, in: context)
            let indexRequest = DBCacheIndex.fetchRequest()
            indexRequest.predicate = NSPredicate(format: "tableName_ = %@ and tableOwner_ = %@", obj.name, obj.owner)
            let indexes = (try? context.fetch(indexRequest)) ?? []
            for index in indexes {
                try? deleteIndexColumns(for: index, in: context)
                context.delete(index)
            }
            let triggerRequest = DBCacheTrigger.fetchRequest()
            triggerRequest.predicate = NSPredicate(format: "objectName = %@ and objectOwner = %@", obj.name, obj.owner)
            let triggers = (try? context.fetch(triggerRequest)) ?? []
            for trigger in triggers { context.delete(trigger) }
            dropManagedObject(table, with: context)
        case .index:
            let request = DBCacheIndex.fetchRequest()
            request.predicate = NSPredicate(format: "name_ = %@ and owner_ = %@", obj.name, obj.owner)
            let index = (try? context.fetch(request))?.first
            try? deleteIndexColumns(for: index, in: context)
            dropManagedObject(index, with: context)
        case .type, .package:
            let request = DBCacheSource.fetchRequest()
            request.predicate = NSPredicate(format: "name_ = %@ and owner_ = %@", obj.name, obj.owner)
            let src = (try? context.fetch(request))?.first
            dropManagedObject(src, with: context)
        default:
            break
        }
        context.delete(obj)
    }

    nonisolated func dropManagedObject(_ obj: NSManagedObject?, with context: NSManagedObjectContext) {
        guard let obj else { return }
        context.delete(obj)
    }

    // MARK: - Source view support

    func getSource(dbObject: DBCacheObject) async -> String {
        let name = dbObject.name
        let owner = dbObject.owner
        let type = OracleObjectType(rawValue: dbObject.type) ?? .unknown
        switch type {
        case .package, .type:
            return await self.backgroundFetchString { context in
                let request = DBCacheSource.fetchRequest()
                request.predicate = NSPredicate(format: "name_ = %@ and owner_ = %@", name, owner)
                let results = (try? context.fetch(request)) ?? []
                if let obj = results.first {
                    return (obj.textSpec ?? "") + "\n\n\n" + (obj.textBody ?? "")
                }
                return ""
            }
        case .view:
            return await self.backgroundFetchString { context in
                let request = DBCacheTable.fetchRequest()
                request.predicate = NSPredicate(format: "name_ = %@ and owner_ = %@", name, owner)
                let results = (try? context.fetch(request)) ?? []
                if let obj = results.first { return obj.sqltext ?? "" }
                return ""
            }
        default:
            return "to be developed"
        }
    }

    private func backgroundFetchString(_ body: @escaping @Sendable (NSManagedObjectContext) -> String) async -> String {
        let context = persistenceController.container.newBackgroundContext()
        return await context.perform {
            body(context)
        }
    }

    func editSource(dbObject: DBCacheObject) async -> URL? {
        let text = await getSource(dbObject: dbObject)
        var newModel = MainModel(text: text)
        newModel.connectionDetails = self.connDetails
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let temporaryFilename = "\(UUID().uuidString).macintora"
        let temporaryFileURL = temporaryDirectoryURL.appendingPathComponent(temporaryFilename)
        do {
            let data = try JSONEncoder().encode(newModel)
            if FileManager.default.createFile(atPath: temporaryFileURL.path, contents: data, attributes: nil) {
                return temporaryFileURL
            } else {
                return nil
            }
        } catch {
            log.error("File write failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - DB metadata

    func updateConnDatabase() async {
        let context = persistenceController.container.newBackgroundContext()
        let request = ConnDatabase.fetchRequest(tns: connDetails.tns)
        let dbs = (try? context.fetch(request)) ?? []
        let localDbVersionFull: String
        let localDbVersionMajor: Int
        var localLastUpdate: Date?
        do {
            (localDbVersionFull, localDbVersionMajor) = try await getDBVersion()
        } catch {
            log.cache.error("Could not get DB version, \(error.localizedDescription, privacy: .public)")
            return
        }
        let dbid: Int64
        do {
            dbid = try await Int64(getDBid())
        } catch {
            log.cache.error("Could not get DBID, \(error.localizedDescription, privacy: .public)")
            return
        }

        if let db = dbs.first {
            localLastUpdate = db.lastUpdate
            if localDbVersionFull != db.versionFull {
                db.versionFull = localDbVersionFull
                db.versionMajor = Int16(localDbVersionMajor)
            }
            if dbid != db.dbid {
                db.dbid = dbid
                clearCache()
            }
            try? context.save()
        } else {
            let db = ConnDatabase(context: context)
            db.tnsAlias = connDetails.tns
            db.versionFull = localDbVersionFull
            db.versionMajor = Int16(localDbVersionMajor)
            db.dbid = dbid
            db.objectWillChange.send()
            try? context.save()
            localLastUpdate = nil
        }
        let finalVersionFull = localDbVersionFull
        let finalVersionMajor = localDbVersionMajor
        let finalLastUpdate = localLastUpdate
        await MainActor.run {
            self.dbVersionFull = finalVersionFull
            self.dbVersionMajor = finalVersionMajor
            self.lastUpdate = finalLastUpdate
        }
    }

    func getDBid() async throws -> Int {
        let logger = oracleLogger
        return try await withClient { conn -> Int in
            var dbid: Int = 0
            var isCDB = false
            let stream = try await conn.execute("select dbid, cdb from v$database", logger: logger)
            for try await row in stream {
                let rr = row.makeRandomAccess()
                dbid = rr.optInt("DBID") ?? 0
                isCDB = rr.optString("CDB") == "YES"
            }
            if isCDB {
                let stream2 = try await conn.execute(
                    "select dbid from v$pdbs where name = SYS_CONTEXT('USERENV', 'DB_NAME')",
                    logger: logger
                )
                for try await row in stream2 {
                    dbid = row.makeRandomAccess().optInt("DBID") ?? dbid
                }
            }
            return dbid
        }
    }

    func getDBVersion() async throws -> (String, Int) {
        let logger = oracleLogger
        return try await withClient { conn -> (String, Int) in
            var versionFull = ""
            var versionMajor = 0
            let stream = try await conn.execute("select version_full from product_component_version", logger: logger)
            for try await row in stream {
                if let full = row.makeRandomAccess().optString("VERSION_FULL") {
                    versionFull = full
                    if let first = full.components(separatedBy: ".").first, let v = Int(first) {
                        versionMajor = v
                    }
                }
            }
            return (versionFull, versionMajor)
        }
    }

    // MARK: - Misc

    func deleteAll(from entityName: String) async throws {
        // Construct the request *inside* the background closure: NSBatchDeleteRequest
        // isn't Sendable in the post-`@preconcurrency` CoreData import, so capturing
        // one across the actor hop fails the Sendable check. Building it on the
        // background context's thread is also the documented CoreData pattern.
        try await self.backgroundPerformThrowing { context in
            context.automaticallyMergesChangesFromParent = true
            let fetchRequest: NSFetchRequest<any NSFetchRequestResult> = NSFetchRequest(entityName: entityName)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            deleteRequest.resultType = .resultTypeObjectIDs
            let batchDelete = try context.execute(deleteRequest) as? NSBatchDeleteResult
            guard let deleteResult = batchDelete?.result else { return }
            let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: deleteResult as! [NSManagedObjectID]]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
            try? context.save()
        }
    }

    func setLastUpdateAsync(_ value: Date?) async {
        let context = persistenceController.container.newBackgroundContext()
        let request = ConnDatabase.fetchRequest(tns: connDetails.tns)
        let dbs = (try? context.fetch(request)) ?? []
        if let db = dbs.first {
            db.lastUpdate = value
            try? context.save()
            await MainActor.run { self.lastUpdate = value }
        }
    }

    func reportCacheCounts() -> String {
        let context = persistenceController.container.newBackgroundContext()
        let objCount = (try? context.count(for: NSFetchRequest<DBCacheObject>(entityName: "DBCacheObject"))) ?? 0
        let tableCount = (try? context.count(for: NSFetchRequest<DBCacheTable>(entityName: "DBCacheTable"))) ?? 0
        let tableColCount = (try? context.count(for: NSFetchRequest<DBCacheTableColumn>(entityName: "DBCacheTableColumn"))) ?? 0
        let sourceCount = (try? context.count(for: NSFetchRequest<DBCacheSource>(entityName: "DBCacheSource"))) ?? 0
        let indexCount = (try? context.count(for: NSFetchRequest<DBCacheIndex>(entityName: "DBCacheIndex"))) ?? 0
        let indexColCount = (try? context.count(for: NSFetchRequest<DBCacheIndexColumn>(entityName: "DBCacheIndexColumn"))) ?? 0
        return "Cache contents:\n Total objects - \(objCount)\n tables and views - \(tableCount)\n table and view columns - \(tableColCount)\n stored code objects: \(sourceCount)\n indexes - \(indexCount)\n index columns - \(indexColCount)"
    }
}
