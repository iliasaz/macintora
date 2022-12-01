//
//  DBCacheVM.swift
//  DBObjectsBrowser
//
//  Created by Ilia on 5/1/22.
//

import Foundation
import SwiftUI
import SwiftOracle
import os

extension Logger {
    var cache: Logger { Logger(subsystem: Logger.subsystem, category: "cache") }
}

//let oracleObjectTypes = ["CLUSTER","CONSUMER GROUP","CONTAINER","CONTEXT","DATABASE LINK","DESTINATION","DIRECTORY","EDITION","EVALUATION CONTEXT","FUNCTION","INDEX","INDEXTYPE","JAVA CLASS","JAVA DATA","JAVA RESOURCE","JAVA SOURCE","JOB","JOB CLASS","LIBRARY","MATERIALIZED VIEW","OPERATOR","PACKAGE","PROCEDURE","PROGRAM","QUEUE","RESOURCE PLAN","RULE","RULE SET","SCHEDULE","SCHEDULER GROUP","SEQUENCE","SYNONYM","TABLE","TRIGGER","TYPE","UNIFIED AUDIT POLICY","VIEW","WINDOW","XML SCHEMA"]
//let oracleObjectTypes = ["TABLE"]

public enum OracleObjectType: String, CaseIterable, CustomStringConvertible {
    public var description: String {self.rawValue}
    
    case table = "TABLE"
    case view = "VIEW"
    case type = "TYPE"
    case package = "PACKAGE"
    case index = "INDEX"
    case trigger = "TRIGGER"
//    case procedure = "PROCEDURE"
//    case procedure = "FUNCTION"
    case unknown = "UNKNOWN"
}

//let oracleSchemas = ["APPS","CDR","APPS_NE","APPLSYS"]

// select * from dba_objects where object_type in <oracleObjectTypes> and owner not like <oracleSchemaExclusions escape '\\'>

struct OracleObject: CustomStringConvertible {
    
    let owner: String
    let name: String
    let type: OracleObjectType
    let lastDDL: Date
    let createDate: Date
    let editionName: String?
    let isEditionable: Bool
    let isValid: Bool
    let objectId: Int
    
    var description: String {"owner: \(owner), name: \(name), type: \(type), createDate: \(createDate.ISO8601Format()), lasdtDDL: \(lastDDL.ISO8601Format()), objectID: \(objectId), isValid: \(isValid), isEditionable: \(isEditionable), editionName: \(editionName ?? "")"}
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
    
    func startEnqueuing() {
        isCacheEnqueueing = true
    }
    
    func stopEnqueuing() {
        isCacheEnqueueing = false
    }
    
    func startSession() {
        activeSessions += 1
    }
    
    func completeSession() {
        activeSessions -= 1
    }
}


class DBCacheVM: ObservableObject {
    @Published var isConnected = ConnectionStatus.disconnected
    @Published var dbVersionFull: String?
    @Published var lastUpdate: Date?
    @Published var persistenceController: PersistenceController
    @Published var isReloading = false
    
    @AppStorage("cacheUpdatePrefetchSize") private var cacheUpdatePrefetchSize: Int = 10000
    @AppStorage("cacheUpdateBatchSize") private var cacheUpdateBatchSize: Int = 200
    @AppStorage("includeSystemObjects") private var includeSystemObjects = false
    @AppStorage("cacheUpdateSessionLimit") private var cacheUpdateSessionLimit: Int = 5
    
    let connDetails: ConnectionDetails
    private(set) var pool: ConnectionPool? // service connections
    private var objectQueues = [OracleObjectType: ObjectQueue]()
    var dbVersionMajor: Int?
    let dateFormatter: DateFormatter = DateFormatter()
    var cacheState = CacheState()
    var searchCriteria: DBCacheSearchCriteria
    
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
        // create queues
        OracleObjectType.allCases.forEach { objectQueues[$0] = ObjectQueue() }
        if let selected = selectedObjectName {
            searchCriteria.searchText = selected
        }
    }
    
    init(preview: Bool = true) {
        self.connDetails = ConnectionDetails(username: "user", password: "password", tns: "preview", connectionRole: .regular)
        self.searchCriteria = DBCacheSearchCriteria(for: connDetails.tns)
        persistenceController = PersistenceController.preview
        // create queues
        OracleObjectType.allCases.forEach { objectQueues[$0] = ObjectQueue() }
    }
    
    func setConnDetailsFromCache() {
        log.cache.debug("in \(#function, privacy: .public)")
        let context = persistenceController.container.newBackgroundContext()
        let request = ConnDatabase.fetchRequest(tns: connDetails.tns)
        let dbs = (try? context.fetch(request)) ?? []
        if let db = dbs.first {
            log.cache.debug("in \(#function, privacy: .public); found databases: \(dbs, privacy: .public)")
            let lastUpdate = db.lastUpdate
            let dbVerFull = db.versionFull
            Task { [self] in await MainActor.run {
                self.lastUpdate = lastUpdate
                self.dbVersionFull = dbVerFull
            }}
        }
    }
    
    func clearCache() {
        log.cache.debug("in \(#function, privacy: .public)")
        Task.init(priority: .background) {
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
            setLastUpdate(nil)
            await MainActor.run { self.persistenceController.container.viewContext.refreshAllObjects() }
        }
    }
    
    func updateCache(ignoreLastUpdate: Bool = false, withCleanup: Bool = false, cleanupOnly: Bool = false) {
        log.cache.debug("in \(#function, privacy: .public)")
        isReloading = true
        Task.init(priority: .background) {
            if isConnected == .disconnected {
                do {
                    try connectSvc()
                    await MainActor.run { isConnected = .connected }
                    await updateConnDatabase()
                } catch {
                    log.cache.error("could not connect to the database: \(error.localizedDescription, privacy: .public)")
                    await MainActor.run { isConnected = .disconnected }
                    return
                }
            }
            // make sure we actuall can connect
            guard let connCheck = pool?.getConnection() else {
                log.cache.error("could not get a connection from the pool")
                pool = nil
                await MainActor.run { isConnected = .disconnected }
                return
            }
            pool?.returnConnection(conn: connCheck)
            if withCleanup || cleanupOnly {
                await cleanupDroppedObjects()
            }
            if !cleanupOnly {
                await withTaskGroup(of: Void.self) { taskGroup in
                    await cacheState.startEnqueuing()
                    taskGroup.addTask { await self.populateObjectQueues(ignoreLastUpdate: ignoreLastUpdate) }
                    taskGroup.addTask { await self.processObjectQueues() }
                }
                log.cache.debug("finished taskGroup in \(#function, privacy: .public)")
            }
            disconnectSvc()
            await MainActor.run { isConnected = .disconnected }
            await MainActor.run { isReloading = false }
        }
        log.cache.debug("exiting from \(#function, privacy: .public)")
    }
    
    // cleanup local cache objects that no logner exist in the database
    func cleanupDroppedObjects() async {
        await self.persistenceController.container.performBackgroundTask { (context) in
            context.automaticallyMergesChangesFromParent = true
            let request = DBCacheObject.fetchRequest()
            let results = (try? context.fetch(request)) ?? []
            var strVal = ""
            var nexs = [Int]()
            strVal.reserveCapacity(4000)
            for r in results {
                if strVal.lengthOfBytes(using: .utf8) > 3900 {
                    strVal.append(contentsOf: String(r.objectId))
                    nexs.append(contentsOf: self.cleanupDroppedObjectsBatch(for: strVal))
                    strVal.removeAll(keepingCapacity: true)
                } else {
                    strVal.append(contentsOf: String(r.objectId))
                    strVal.append(",")
                }
            }
            // remainder
            if strVal.lengthOfBytes(using: .utf8) > 3900 {
                nexs.append(contentsOf: self.cleanupDroppedObjectsBatch(for: strVal))
                strVal.removeAll(keepingCapacity: true)
            }
            if !nexs.isEmpty {
                self.dropLocalObjectsByIds(nexs, with: context)
                try? context.save()
            }
        }
    }
    
    // take a batch of comma separated object IDs and query them in the database, then remove the ones not existing from the local cache
    func cleanupDroppedObjectsBatch(for idStr: String) -> [Int] {
        log.cache.debug("in \(#function, privacy: .public)")
        var nexs = [Int]()
        let sql = buildCleanupCheckQuery(for: idStr)
        log.cache.debug("executing cleanup sql: \(sql, privacy: .public)")
        guard let conn = pool?.getConnection(tag: "cache", autoCommit: false) else {log.cache.error("could not get a connection"); return [] }
        defer { pool?.returnConnection(conn: conn) }
        let cur = try? conn.cursor()
        try? cur?.execute(sql, prefetchSize: 1000)
        log.cache.debug("finished executing cleanup sql in \(#function, privacy: .public)")
        while let row = cur?.nextSwifty() {
            nexs.append(row["OBJECT_ID"]!.int!)
        }
        log.cache.debug("got array of non-existing objects, count: \(nexs.count)")
        return nexs
    }
    
    func dropLocalObjectsByIds(_ ids: [Int], with context: NSManagedObjectContext) {
        let request = DBCacheObject.fetchRequest()
        request.predicate = NSPredicate(format: "objectId IN %@", ids)
        let results = (try? context.fetch(request)) ?? []
        for r in results {
            dropLocalObject(r, with: context)
        }
    }
    
    func buildCleanupCheckQuery(for ids: String) -> String {
        var sql = """
        with rws as (select '\(ids)' str from dual)
        , ids as (select regexp_substr (str,'[^,]+', 1, level) id
        from rws connect by level <= length ( str ) - length ( replace ( str, ',' ) ) + 1
        )
        select to_number(ids.id) object_id
        from ids
        where not exists (select 1 from dba_objects o where o.object_id = ids.id)
        """
        return sql
    }
    
    func buildObjectQuerySQL(ignoreLastUpdate: Bool = false) -> String {
        var sql = """
select /*+ rule */ owner, object_name, object_type, object_id, created, editionable, edition_name, status
, greatest(last_ddl_time
, nvl(( select last_ddl_time from dba_objects o1 where o1.owner = o.owner and o1.object_name = o.object_name and o1.object_type = o.object_type || ' BODY'), o.last_ddl_time)) as last_ddl_time
from dba_objects o
"""
        sql += " where object_type in ("
        sql += OracleObjectType.allCases.map {"'\($0.rawValue)'"}.joined(separator: ",")
        sql += ") "
//        sql += " and object_type = 'PACKAGE'"
        // check to see if schema filter is applied
        if !searchCriteria.ownerInclusionList.isEmpty {
            sql += " and owner in ("
            sql += searchCriteria.ownerInclusionList.map { "'\($0)'" }.joined(separator: ",")
            sql += ")"
        }
        // include/exclude system objects
        if !includeSystemObjects {
            sql += " and owner NOT in (select username from dba_users where oracle_maintained = 'Y')"
        }
        // check to see if name prefix filter is applied
        if !searchCriteria.namePrefixInclusionList.isEmpty {
            sql += " and ( "
            sql += searchCriteria.namePrefixInclusionList.map { "object_name like '\($0.replacingOccurrences(of: "_", with: #"\_"#))%' escape \(#"'\'"#)" }.joined(separator: " or ")
            sql += ")"
        }
        // exclude system objects - LOB indexes and etc.
        sql += " and object_name not like 'SYS_IL%'"
        // check to see if lastUpdate filter should be applied
        if let lstDate = self.lastUpdate, !ignoreLastUpdate {
            dateFormatter.calendar = Calendar(identifier: .iso8601)
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let lstString = dateFormatter.string(from: lstDate)
            sql += " and ( last_ddl_time > to_date('\(lstString)', 'yyyy-mm-dd hh24:mi:ss') or"
            sql += " exists (select 1 from dba_objects o1 where o1.owner = o.owner and o1.object_name = o.object_name and o1.object_type = o.object_type || ' BODY'"
            sql += " and o1.last_ddl_time > to_date('\(lstString)', 'yyyy-mm-dd hh24:mi:ss') ) )"
        }
//        sql += " and rownum < 11 and object_name like 'CDR%'"
//        sql += " and (object_name like 'CDR%' or object_name like 'DME%') and object_type = 'PACKAGE'"
//        sql += " and (object_name in ('DME_COL_DISP_CHARS_TYPE','DME_AMENDMENT_TYPE'))"
//        sql += " and object_type = 'PACKAGE'"
//        sql += " and (object_name like 'CDR%' or object_name like 'DME%')"
        log.cache.debug("object query SQL: \(sql, privacy: .public)")
        return sql
    }
    
    func populateObjectQueues(ignoreLastUpdate: Bool = false) async {
        log.cache.debug("in \(#function, privacy: .public)")
        if isConnected != .connected { log.cache.error("Not connected to Oracle database"); return }
//        await cacheState.startEnqueuing() <<< this has been moved to the caller updateCache to make sure it is invoked before processObjectQueues
        let sql = buildObjectQuerySQL(ignoreLastUpdate: ignoreLastUpdate)
        await cacheState.startSession()
        guard let conn = pool?.getConnection(tag: "cache", autoCommit: false) else {log.cache.error("could not get a connection"); return }
        defer { pool?.returnConnection(conn: conn) }
        let cur = try? conn.cursor()
        try? cur?.execute(sql, prefetchSize: cacheUpdatePrefetchSize)
        log.cache.debug("finished executing select statement in \(#function, privacy: .public)")
        while let row = cur?.nextSwifty() {
            let obj = OracleObject(owner: row["OWNER"]!.string!,
                                   name: row["OBJECT_NAME"]!.string!,
                                   type: OracleObjectType(rawValue: row["OBJECT_TYPE"]!.string!) ?? .unknown,
                                   lastDDL: row["LAST_DDL_TIME"]!.date!,
                                   createDate: row["CREATED"]!.date!,
                                   editionName: row["EDITION_NAME"]!.string,
                                   isEditionable: row["EDITIONABLE"]!.string == "Y",
                                   isValid: row["STATUS"]!.string == "VALID",
                                   objectId: row["OBJECT_ID"]!.int!
            )
//            log.cache.debug("adding \(obj, privacy: .public) to queue \(obj.type, privacy: .public)")
            await objectQueues[obj.type]?.enqueue(obj)
        }
        await cacheState.stopEnqueuing()
        await cacheState.completeSession()
        log.cache.debug("stopped enqueueing")
        // get the sum of all queue lengths
        let qlen = await objectQueues.asyncMap( { await $0.value.length } ).reduce(0, { $0 + $1 })
        log.cache.debug("exiting from \(#function, privacy: .public); queue length: \(qlen, privacy: .public)")
    }
    
    func processObjectQueues() async {
        log.cache.debug("in \(#function, privacy: .public)")
        // save the date when we started processing
        let updateDate = Date.now
        // work through the queue
        await withTaskGroup(of: Void.self) { taskGroup in
            for q in objectQueues {
                taskGroup.addTask {
                    await self.processObjectQueue(for: q.key)
                }
            }
        }
        log.cache.debug("finished taskGroup in \(#function, privacy: .public)")
        setLastUpdate(updateDate)
        log.cache.debug("exiting from \(#function, privacy: .public)")
    }
    
    func processObjectQueue(for objectType: OracleObjectType) async {
        log.cache.debug("in \(#function, privacy: .public) for queue: \(objectType, privacy: .public)")
        let q = self.objectQueues[objectType]!
        var objs = [OracleObject]()
        var iter = 0
        repeat {
            while let obj = await q.dequeue() {
                objs.append(obj)
                iter += 1
                if iter%cacheUpdateBatchSize == 0 {
                    while true {
                        if await cacheState.activeSessions >= cacheUpdateSessionLimit {
                            log.cache.debug("No connections available; suspending task for \(objectType.rawValue, privacy: .public)")
                            await Task.yield()
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                        } else { break }
                    }
                    let objstemp = objs
                    await cacheState.startSession()
                    if objectType == .package || objectType == .type {
                        await self.processSource_NEW(objs)
                    } else {
                        await self.processChunkOfObjects(objstemp, objectType: objectType)
                    }
                    await cacheState.completeSession()
                    objs.removeAll()
                    log.cache.debug("processed \(iter, privacy: .public) objects from queue \(objectType, privacy: .public)")
                }
            }
            log.cache.debug("queue \(objectType, privacy: .public) is empty")
            // the remainder
            if objs.count > 0 {
                while true {
                    if await cacheState.activeSessions >= cacheUpdateSessionLimit {
                        log.cache.debug("No connections available; suspending task for \(objectType.rawValue, privacy: .public)")
                        await Task.yield()
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                    } else { break }
                }
                log.cache.debug("remaining items in queue \(objectType, privacy: .public)")
                let objstemp = objs
                await cacheState.startSession()
                if objectType == .package || objectType == .type {
                    await self.processSource_NEW(objs)
                } else {
                    await self.processChunkOfObjects(objstemp, objectType: objectType)
                }
                await cacheState.completeSession()
                objs.removeAll()
            }
            // exit if not currently enqueueing, otherwise wait and repeat
            if !(await cacheState.isCacheEnqueueing) {
                log.cache.debug("not enqueueing")
                break
            }
            else {
                log.cache.debug("still enqueueing")
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        } while true

        log.cache.debug("exiting from \(#function, privacy: .public); processed \(iter, privacy: .public) objects from queue \(objectType, privacy: .public)")
    }
    
    func processChunkOfObjects(_ objs: [OracleObject], objectType: OracleObjectType) async {
        log.cache.debug("in \(#function, privacy: .public) for queue: \(objectType, privacy: .public) in thread \(Thread.current, privacy: .public)")
        await self.persistenceController.container.performBackgroundTask { (context) in
            switch objectType {
                case .table, .view:
                    self.processTables(objs, context: context, isView: objectType == .view)
//                case .type, .package:
//                    self.processSource(objs, context: context)
                case .index:
                    self.processIndexes(objs, context: context)
                case .trigger:
                    self.processTriggers(objs, context: context)
                case .unknown:
                    log.cache.error("Unsupported Oracle object type for objects \(objs, privacy: .public)")
                default:
                    log.cache.error("Unsupported Oracle object type for objects \(objs, privacy: .public)")
            }
            log.cache.debug("calling processObjects for a chunk of \(objectType, privacy: .public)")
            self.processObjects(objs, context: context)
            log.cache.debug("saving context for a chunk of \(objectType, privacy: .public)")
            do { try context.save() }
            catch { log.cache.error("failed to save context for a chunk of \(objectType, privacy: .public)"); fatalError("Failure to save context: \(error)") }
        }
        log.cache.debug("exiting from \(#function, privacy: .public) for queue \(objectType, privacy: .public)")
    }
    
    func processObjects(_ objs: [OracleObject], context: NSManagedObjectContext) {
        log.cache.debug("in \(#function, privacy: .public)")
        let request = DBCacheObject.fetchRequest()
        // TODO: should consider array processing here
        for obj in objs {
            request.predicate = NSPredicate(format: "name_ = %@ and owner_ = %@ and type_ = %@ ", obj.name, obj.owner, obj.type.rawValue)
            let results = (try? context.fetch(request)) ?? []
            if let objCache = results.first {
                log.cache.debug("updating existing db object \(obj.owner, privacy: .public).\(obj.name, privacy: .public) of type \(obj.type.rawValue, privacy: .public)")
                objCache.lastDDLDate = obj.lastDDL
                objCache.createDate = obj.createDate
                objCache.editionName = obj.editionName
                objCache.isEditionable = obj.isEditionable
                objCache.isValid = obj.isValid
                objCache.objectId = obj.objectId
            } else {
                log.cache.debug("creating a new db object \(obj.owner, privacy: .public).\(obj.name, privacy: .public) of type \(obj.type.rawValue, privacy: .public)")
                let objCache = DBCacheObject(context: context)
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
        log.cache.debug("exiting from \(#function, privacy: .public)")
    }
    
    func processTables(_ objs: [OracleObject], context: NSManagedObjectContext, isView: Bool) {
//        log.cache.debug("in \(#function, privacy: .public)")
        guard objs.count > 0 else { return }
        var sql: String
        if isView {
            sql = "select owner, view_name table_name, 0 num_rows, null last_analyzed, 'NO' partitioned, editioning_view, read_only, text from dba_views where (owner, view_name) in ("
        } else {
            sql = "select owner, table_name, num_rows, last_analyzed, partitioned, 'N' editioning_view, 'N' read_only, null text from dba_tables where (owner, table_name) in ("
        }
        var iter = 0
        var bindvars = [String]()
        var params = [String: BindVar]()
        for obj in objs {
            bindvars.append("(:o\(iter), :n\(iter))")
            params[":o\(iter)"] = BindVar(obj.owner)
            params[":n\(iter)"] = BindVar(obj.name)
            iter += 1
        }
        sql += bindvars.joined(separator: ",")
        sql += ")"
        guard let conn = pool?.getConnection(tag: "cache", autoCommit: false) else {log.cache.error("could not get a connection"); return }
        defer { pool?.returnConnection(conn: conn) }
//        log.cache.debug("in \(#function, privacy: .public), executing SQL: \(sql, privacy: .public) with objects: \(objs, privacy: .public)")
        let cur = try? conn.cursor()
        do {
            try cur?.execute(sql, params: params, prefetchSize: 1000)
        } catch { log.cache.error("\(error.localizedDescription, privacy: .public)") }
        let request = DBCacheTable.fetchRequest()
        while let row = cur?.nextSwifty() {
            let tableName = (row["TABLE_NAME"]?.string)!
            let tableOwner = (row["OWNER"]?.string)!
            let numRows = (row["NUM_ROWS"]?.int) ?? 0
            let lastAnalyzed = row["LAST_ANALYZED"]?.date
            let isPartitioned = row["PARTITIONED"]?.string == "YES"
            let sqltext = row["TEXT"]?.string
            let isEditioning = row["EDITIONING_VIEW"]?.string == "Y"
            let isReadOnly = row["READ_ONLY"]?.string == "Y"
            // see if the object is already in cache
            request.predicate = NSPredicate(format: "name_ = %@ and owner_ = %@", tableName, tableOwner)
            let results = (try? context.fetch(request)) ?? []
            if let obj = results.first {
//                log.cache.debug("Table found in cache: \(tableOwner).\(tableName)")
                obj.numRows = Int64(numRows)
                obj.lastAnalyzed = lastAnalyzed
                obj.isPartitioned = isPartitioned
                obj.isView = isView
                // view specific fields
                obj.isEditioning = isEditioning
                obj.isReadOnly = isReadOnly
                if isView {
                    obj.sqltext = "create or replace\(isEditioning ? " editioning" : "") view \(tableOwner).\(tableName) as ".appending(sqltext ?? "")
                }
                // now drop columns, they will be re-populated
                try? deleteTableColumns(for: obj, in: context)
                populateTableColumns(for: obj, in: context, using: conn)
            } else {
//                log.cache.debug("creating a new cache instance for table \(tableOwner, privacy: .public).\(tableName, privacy: .public)")
                let obj = DBCacheTable(context: context)
                obj.isView = isView
                obj.owner_ = tableOwner
                obj.name_ = tableName
                obj.numRows = Int64(numRows)
                obj.lastAnalyzed = row["LAST_ANALYZED"]?.date
                obj.isPartitioned = isPartitioned
                // view specific fields
                obj.isEditioning = isEditioning
                obj.isReadOnly = isReadOnly
                if isView {
                    obj.sqltext = "create or replace\(isEditioning ? " editioning" : "") view \(tableOwner).\(tableName) as ".appending(sqltext ?? "")
                }
                populateTableColumns(for: obj, in: context, using: conn)
            }
        }
//        log.cache.debug("exiting from \(#function, privacy: .public)")
    }
    
    func populateTableColumns(for table: DBCacheTable, in context: NSManagedObjectContext, using conn: PooledConnection) {
//        log.cache.debug("populating columns for table \(table.owner, privacy: .public).\(table.name, privacy: .public)")
        let sql = "select owner, table_name, column_name, data_type, data_precision, data_scale, data_length, nullable, column_id, data_default, num_distinct, identity_column, num_nulls, hidden_column, virtual_column, user_generated, internal_column_id from dba_tab_cols where owner = :owner and table_name = :tableName"
        let cur = try? conn.cursor()
        try? cur?.execute(sql, params: [":owner": BindVar(table.owner), ":tableName": BindVar(table.name)])
        var cnt = 0
        while let row = cur?.nextSwifty() {
            let col = DBCacheTableColumn(context: context)
            col.isNullable = row["NULLABLE"]!.string == "Y"
            col.dataType_ = row["DATA_TYPE"]!.string
            col.columnID = row["COLUMN_ID"]!.isNull ? nil : NSNumber(value: row["COLUMN_ID"]!.int!)
            col.internalColumnID = Int16(row["INTERNAL_COLUMN_ID"]!.int!)
            col.columnName_ = row["COLUMN_NAME"]!.string
            col.length = Int32(row["DATA_LENGTH"]!.int!)
            col.defaultValue = row["DATA_DEFAULT"]!.string
            col.isIdentity = row["IDENTITY_COLUMN"]!.string == "YES"
            col.isHidden = row["HIDDEN_COLUMN"]!.string == "YES"
            col.isVirtual = row["VIRTUAL_COLUMN"]!.string == "YES"
            col.isSysGen = row["USER_GENERATED"]!.string != "YES"
            col.numNulls = Int64(row["NUM_NULLS"]!.int ?? 0)
            col.numDistinct = Int64(row["NUM_DISTINCT"]!.int ?? 0)
            col.precision = row["DATA_PRECISION"]!.isNull ? nil : NSNumber(value: row["DATA_PRECISION"]!.int!)
            col.scale = row["DATA_SCALE"]!.isNull ? nil : NSNumber(value: row["DATA_SCALE"]!.int!)
            col.owner_ = table.owner_
            col.tableName_ = table.name_
            cnt += 1
        }
//        log.cache.debug("exiting from \(#function, privacy: .public); added \(cnt) columns in table \(table.owner, privacy: .public).\(table.name, privacy: .public)")
    }
    
    func processIndexes(_ objs: [OracleObject], context: NSManagedObjectContext) {
//        log.cache.debug("in \(#function, privacy: .public)")
        guard objs.count > 0 else { return }
        var sql = "select owner, index_name, index_type, table_owner, table_name, tablespace_name, uniqueness, leaf_blocks, distinct_keys, avg_leaf_blocks_per_key, avg_data_blocks_per_key, clustering_factor, status, num_rows, sample_size, last_analyzed, degree, partitioned, visibility from dba_indexes where index_type != 'LOB' and (owner, index_name) in ("
        var iter = 0
        var bindvars = [String]()
        var params = [String: BindVar]()
        for obj in objs {
            bindvars.append("(:o\(iter), :n\(iter))")
            params[":o\(iter)"] = BindVar(obj.owner)
            params[":n\(iter)"] = BindVar(obj.name)
            iter += 1
        }
        sql += bindvars.joined(separator: ",")
        sql += ")"
        guard let conn = pool?.getConnection(tag: "cache", autoCommit: false) else {log.cache.error("could not get a connection"); return }
        defer { pool?.returnConnection(conn: conn) }
//        log.cache.debug("in \(#function, privacy: .public), executing SQL: \(sql, privacy: .public) with objects: \(objs, privacy: .public)")
        let cur = try? conn.cursor()
        do {
            try cur?.execute(sql, params: params, prefetchSize: 1000)
        } catch { log.cache.error("\(error.localizedDescription)") }
        let request = DBCacheIndex.fetchRequest()
        while let row = cur?.nextSwifty() {
            let indexOwner = (row["OWNER"]!.string)!
            let indexName = (row["INDEX_NAME"]!.string)!
            let indexType = (row["INDEX_TYPE"]!.string)!
            let tableOwner = (row["TABLE_OWNER"]!.string)!
            let tableName = (row["TABLE_NAME"]!.string)!
            let tablespaceName = row["TABLESPACE_NAME"]!.string
            let isUnique = row["UNIQUENESS"]!.string == "UNIQUE"
            let leafBlocks = (row["LEAF_BLOCKS"]!.int) ?? 0
            let distinctKeys = (row["DISTINCT_KEYS"]!.int) ?? 0
            let avgLeafBlocksPerKey = (row["AVG_LEAF_BLOCKS_PER_KEY"]!.double) ?? 0
            let avgDataBlocksPerKey = (row["AVG_DATA_BLOCKS_PER_KEY"]!.double) ?? 0
            let clusteringFactor = (row["CLUSTERING_FACTOR"]!.int) ?? 0
            let isValid = row["STATUS"]!.string == "VALID"
            let numRows = (row["NUM_ROWS"]!.int) ?? 0
            let sampleSize = row["SAMPLE_SIZE"]!.int ?? 0
            let lastAnalyzed = row["LAST_ANALYZED"]?.date
            let degree = row["DEGREE"]?.string
            let isPartitioned = row["PARTITIONED"]?.string == "YES"
            let isVisible = row["VISIBILITY"]?.string == "VISIBLE"
            // see if the object is already in cache
            request.predicate = NSPredicate(format: "name_ = %@ and owner_ = %@", indexName, indexOwner)
            let results = (try? context.fetch(request)) ?? []
            if let obj = results.first {
//                log.cache.debug("Index found in cache: \(indexOwner).\(indexName)")
                obj.type_ = indexType
                obj.tableOwner = tableOwner
                obj.tableName = tableName
                obj.tablespaceName_ = tablespaceName
                obj.isUnique = isUnique
                obj.leafBlocks = Int64(leafBlocks)
                obj.distinctKeys = Int64(distinctKeys)
                obj.avgLeafBlocksPerKey = Double(avgLeafBlocksPerKey)
                obj.avgDataBlocksPerKey = Double(avgDataBlocksPerKey)
                obj.clusteringFactor = Int64(clusteringFactor)
                obj.isValid = isValid
                obj.numRows = Int64(numRows)
                obj.sampleSize = Int64(sampleSize)
                obj.lastAnalyzed = lastAnalyzed
                obj.degree_ = degree
                obj.isPartitioned = isPartitioned
                obj.isVisible = isVisible
                // now drop columns, they will be re-populated
                try? deleteIndexColumns(for: obj, in: context)
                populateIndexColumns(for: obj, in: context, using: conn)
            } else {
//                log.cache.debug("creating a new cache instance for index \(indexOwner, privacy: .public).\(indexName, privacy: .public)")
                let obj = DBCacheIndex(context: context)
                obj.owner_ = indexOwner
                obj.name_ = indexName
                obj.type_ = indexType
                obj.tableOwner = tableOwner
                obj.tableName = tableName
                obj.tablespaceName_ = tablespaceName
                obj.isUnique = isUnique
                obj.leafBlocks = Int64(leafBlocks)
                obj.distinctKeys = Int64(distinctKeys)
                obj.avgLeafBlocksPerKey = Double(avgLeafBlocksPerKey)
                obj.avgDataBlocksPerKey = Double(avgDataBlocksPerKey)
                obj.clusteringFactor = Int64(clusteringFactor)
                obj.isValid = isValid
                obj.numRows = Int64(numRows)
                obj.sampleSize = Int64(sampleSize)
                obj.lastAnalyzed = lastAnalyzed
                obj.degree_ = degree
                obj.isPartitioned = isPartitioned
                obj.isVisible = isVisible
                populateIndexColumns(for: obj, in: context, using: conn)
            }
        }
//        log.cache.debug("exiting from \(#function, privacy: .public)")
    }
    
    func populateIndexColumns(for table: DBCacheIndex, in context: NSManagedObjectContext, using conn: PooledConnection) {
//        log.cache.debug("populating columns for table \(table.owner, privacy: .public).\(table.name, privacy: .public)")
        let sql = "select index_owner, index_name, column_name, column_position, column_length, descend from dba_ind_columns where index_owner = :owner and index_name = :indexName"
        let cur = try? conn.cursor()
        try? cur?.execute(sql, params: [":owner": BindVar(table.owner), ":indexName": BindVar(table.name)])
        var cnt = 0
        while let row = cur?.nextSwifty() {
            let col = DBCacheIndexColumn(context: context)
            col.isDescending = row["DESCEND"]!.string == "DESC"
            col.position = Int16(row["COLUMN_POSITION"]!.int ?? 0)
            col.columnName_ = row["COLUMN_NAME"]!.string
            col.length = Int32(row["COLUMN_LENGTH"]!.int ?? 0)
            col.owner_ = table.owner_
            col.indexName_ = table.name_
            cnt += 1
        }
//        log.cache.debug("exiting from \(#function, privacy: .public); added \(cnt) columns in index \(table.owner, privacy: .public).\(table.name, privacy: .public)")
    }
    
    func deleteTableColumns(for table: DBCacheTable?, in context: NSManagedObjectContext) throws {
        guard let table else { return }
//        log.cache.debug("\(#function, privacy: .public) Deleting table columns from \(table.owner, privacy: .public).\(table.name, privacy: .public)")
        let fetchRequest: NSFetchRequest<NSFetchRequestResult>
        fetchRequest = NSFetchRequest(entityName: "DBCacheTableColumn")
        fetchRequest.predicate = NSPredicate(format: "owner_ = %@ and tableName_ = %@", table.owner, table.name)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        deleteRequest.resultType = .resultTypeObjectIDs
        let batchDelete = try context.execute(deleteRequest) as? NSBatchDeleteResult
        guard let deleteResult = batchDelete?.result else { log.cache.debug("nothing to delete for table \(table.owner).\(table.name)"); return }
        // sync up with in-memory state
        let changes: [AnyHashable: Any] = [ NSDeletedObjectsKey: deleteResult as! [NSManagedObjectID] ]
//        log.cache.debug("merging context after deleting columns for table \(table.owner).\(table.name)")
        if !changes.isEmpty {
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        }
//        log.cache.debug("exiting from \(#function, privacy: .public); deletion of columns for \(table.owner, privacy: .public).\(table.name, privacy: .public) finished")
    }
    
    func deleteIndexColumns(for table: DBCacheIndex?, in context: NSManagedObjectContext) throws {
        guard let table else { return }
//        log.cache.debug("\(#function, privacy: .public) Deleting index columns from \(table.owner, privacy: .public).\(table.name, privacy: .public)")
        let fetchRequest: NSFetchRequest<NSFetchRequestResult>
        fetchRequest = NSFetchRequest(entityName: "DBCacheIndexColumn")
        fetchRequest.predicate = NSPredicate(format: "owner_ = %@ and indexName_ = %@", table.owner, table.name)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        deleteRequest.resultType = .resultTypeObjectIDs
        let batchDelete = try context.execute(deleteRequest) as? NSBatchDeleteResult
        guard let deleteResult = batchDelete?.result else { log.cache.debug("nothing to delete for index \(table.owner).\(table.name)"); return }
        // sync up with in-memory state
        let changes: [AnyHashable: Any] = [ NSDeletedObjectsKey: deleteResult as! [NSManagedObjectID] ]
//        log.cache.debug("merging context after deleting columns for index \(table.owner).\(table.name)")
        if !changes.isEmpty {
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        }
//        log.cache.debug("exiting from \(#function, privacy: .public); deletion of index columns for \(table.owner, privacy: .public).\(table.name, privacy: .public) finished")
    }
    
    private struct TempObj: Hashable {
        let owner: String, name: String
    }
    
    private struct TempSource {
        var textSpec: String?, textBody: String?
    }
    
    func processSource_NEW(_ objs: [OracleObject]) async {
        log.cache.debug("in \(#function, privacy: .public)")
        guard objs.count > 0 else { return }
        guard objs.count < 1000 else { log.cache.error("Unexpected obj count: \(objs.count, privacy: .public)"); fatalError("Unexpected obj count: \(objs.count)") }
        var sql = "select type, owner, name, text from dba_source where owner in ($OWNERS$) and name in ($NAMES$) and type in (:ts, :tb) order by type, owner, name, line"
        guard let conn = pool?.getConnection(tag: "cache", autoCommit: false) else {log.cache.error("could not get a connection"); return }
        defer { pool?.returnConnection(conn: conn) }
        let owners = objs.map { $0.owner }.unique()
        let names = objs.map { $0.name }.unique()
        // build bind var placeholders
        // list of owners
        var paramOwners: [String: BindVar] = [:]
        paramOwners.reserveCapacity(owners.count)
        paramOwners = owners.enumerated().reduce([String: BindVar]()) { (dict, elem) in
            var dict = dict
            dict[":o\(elem.offset)"] = BindVar(elem.element)
            return dict
        }
        // list of names
        var paramNames: [String: BindVar] = [:]
        paramNames.reserveCapacity(names.count)
        paramNames = names.enumerated().reduce([String: BindVar]()) { (dict, elem) in
            var dict = dict
            dict[":n\(elem.offset)"] = BindVar(elem.element)
            return dict
        }
        // list of types
        let paramTypes = [":ts": BindVar(objs[0].type.rawValue), ":tb": BindVar(objs[0].type.rawValue + " BODY")]
        // put it all together
        let params = paramOwners.merging(paramNames) { (current, _) in current }.merging(paramTypes) { (current, _) in current }
        let ownerString = paramOwners.keys.joined(separator: ",")
        let nameString = paramNames.keys.joined(separator: ",")
        sql = sql.replacingOccurrences(of: "$OWNERS$", with: ownerString)
        sql = sql.replacingOccurrences(of: "$NAMES$", with: nameString)
        // execute SQL
        let cur = try? conn.cursor()
        log.cache.debug("executing SQL \(sql, privacy: .public)")
        do { try cur?.execute(sql, params: params, prefetchSize: 50000) }
        catch { log.cache.error("\(error.localizedDescription)") }
        // now scroll through the results and pull all hte details into a temp set
        var text = ""
        var key = ("","","")
        var tempObjs = [TempObj : TempSource]()
        tempObjs.reserveCapacity(objs.count)
        // first row
        guard let row = cur?.nextSwifty() else { log.cache.debug("source not found"); return }
        key = (row["TYPE"]!.string!, row["OWNER"]!.string!, row["NAME"]!.string!)
        text.append(contentsOf: row["TEXT"]!.string ?? "")
        // process all rows
        while let row = cur?.nextSwifty() {
            let newKey = (row["TYPE"]!.string!, row["OWNER"]!.string!, row["NAME"]!.string!)
            if newKey == key { // keep accumulating the source text
                text.append(contentsOf: row["TEXT"]!.string ?? "")
            } else { // done accumulating and switched to the next object
                text = "create or replace ".appending(text)
                let to = TempObj(owner: key.1, name: key.2)
                if tempObjs.keys.contains(to) { // existing obj
                    if key.0.contains("BODY") {
                        tempObjs[to]!.textBody = text
                    } else {
                        tempObjs[to]!.textSpec = text
                    }
                } else { // new obj
                    if key.0.contains("BODY") {
                        tempObjs[to] = TempSource(textSpec: nil, textBody: text)
                    } else {
                        tempObjs[to] = TempSource(textSpec: text, textBody: nil)
                    }
                }
                text.removeAll()
                text.append(contentsOf: row["TEXT"]!.string ?? "")
                key = newKey
            }
        }
        // last row
        text = "create or replace ".appending(text)
        let to = TempObj(owner: key.1, name: key.2)
        if tempObjs.keys.contains(to) { // existing obj
            if key.0.contains("BODY") {
                tempObjs[to]!.textBody = text
            } else {
                tempObjs[to]!.textSpec = text
            }
        } else { // new obj
            if key.0.contains("BODY") {
                tempObjs[to] = TempSource(textSpec: nil, textBody: text)
            } else {
                tempObjs[to] = TempSource(textSpec: text, textBody: nil)
            }
        }
        log.cache.debug("temp objects: \(tempObjs.count)")
        // now that we have all the objects, let's update the cache
        await updateSourceCache(tempObjs: tempObjs, objs: objs)
    }
    
    private func updateSourceCache(tempObjs: [TempObj : TempSource], objs: [OracleObject]) async {
        await self.persistenceController.container.performBackgroundTask { (context) in
            let request = DBCacheSource.fetchRequest()
            // see if the object is already in cache
            for obj in tempObjs {
                request.predicate = NSPredicate(format: "name_ = %@ and owner_ = %@", obj.key.name , obj.key.owner)
                let results = (try? context.fetch(request)) ?? []
                if let cachedObj = results.first {
    //                log.cache.debug("Source found in cache: \(cachedObj.owner, privacy: .public).\(cachedObj.name, privacy: .public)")
                    cachedObj.textSpec = obj.value.textSpec
                    cachedObj.textBody = obj.value.textBody
                } else {
    //                log.cache.debug("creating a new cache instance for source \(obj.type, privacy: .public) - \(obj.owner, privacy: .public).\(obj.name, privacy: .public)")
                    let cachedObj = DBCacheSource(context: context)
                    cachedObj.name = obj.key.name
                    cachedObj.owner = obj.key.owner
                    cachedObj.textSpec = obj.value.textSpec
                    cachedObj.textBody = obj.value.textBody
                }
            }
            // let's not forget to update DBCacheObjects
            log.cache.debug("calling processObjects for a chunk of source")
            self.processObjects(objs, context: context)
            log.cache.debug("saving context for a chunk of source")
            do { try context.save() }
            catch { log.cache.error("failed to save context for a chunk of source"); fatalError("Failure to save context: \(error)") }
        }
    }
    
    func refreshObject(_ currentObj: OracleObject) async {
        log.cache.debug("in \(#function, privacy: .public)")
        // get a database version of the object
        let sql = """
select /*+ rule */ owner, object_name, object_type, object_id, created, editionable, edition_name, status
, greatest(last_ddl_time
, nvl(( select last_ddl_time from dba_objects o1 where o1.owner = o.owner and o1.object_name = o.object_name and o1.object_type = o.object_type || ' BODY'), o.last_ddl_time)) as last_ddl_time
from dba_objects o
where object_type = :type and owner = :owner and object_name = :name
"""
        guard let conn = pool?.getConnection(tag: "cache", autoCommit: false) else {log.cache.error("could not get a connection"); return }
        defer { pool?.returnConnection(conn: conn) }
        let cur = try? conn.cursor()
        log.cache.debug("Executing single object refresh, sql: \(sql, privacy: .public)")
        do { try cur?.execute(sql, params: [":type": BindVar(currentObj.type.rawValue), ":owner": BindVar(currentObj.owner), ":name": BindVar(currentObj.name) ], prefetchSize: 10) }
        catch { log.error("\(error.localizedDescription)"); return }
        log.cache.debug("finished executing select statement in \(#function, privacy: .public)")
        if let row = cur?.fetchOneSwifty() {
            log.cache.debug("got db object \(row["OWNER"]!.string ?? "", privacy: .public).\(row["OBJECT_NAME"]!.string ?? "")")
            let obj = OracleObject(owner: row["OWNER"]!.string!,
                                   name: row["OBJECT_NAME"]!.string!,
                                   type: OracleObjectType(rawValue: row["OBJECT_TYPE"]!.string!) ?? .unknown,
                                   lastDDL: row["LAST_DDL_TIME"]!.date!,
                                   createDate: row["CREATED"]!.date!,
                                   editionName: row["EDITION_NAME"]!.string,
                                   isEditionable: row["EDITIONABLE"]!.string == "Y",
                                   isValid: row["STATUS"]!.string == "VALID",
                                   objectId: row["OBJECT_ID"]!.int!
            )
            if currentObj.type == .package || currentObj.type == .type {
                await self.processSource_NEW([obj])
            } else {
                await self.processChunkOfObjects([obj], objectType: obj.type)
            }
        } else { // no object in the database, should drop it from the cache
            await dropLocalObject(currentObj)
        }
    }
    
    func dropLocalObject(_ obj: OracleObject) async {
        log.cache.debug("in \(#function, privacy: .public)")
        await persistenceController.container.performBackgroundTask { (context) in
            let request = DBCacheObject.fetchRequest()
            request.predicate = NSPredicate(format: "name_ = %@ and owner_ = %@ and type_ = %@ ", obj.name, obj.owner, obj.type.rawValue)
            let results = (try? context.fetch(request)) ?? []
            if let objCache = results.first {
                log.cache.debug("deleting an existing cache object \(obj.owner, privacy: .public).\(obj.name, privacy: .public) of type \(obj.type.rawValue, privacy: .public)")
                context.delete(objCache)
                try? context.save()
            }
        }
        log.cache.debug("exiting from \(#function, privacy: .public)")
    }
    
    func dropLocalObject(_ obj: DBCacheObject, with context: NSManagedObjectContext) {
        log.cache.debug("in \(#function, privacy: .public)")
        switch OracleObjectType(rawValue: obj.type) {
            case .table, .view:
                // get table object
                let tableRequest = DBCacheTable.fetchRequest()
                tableRequest.predicate = NSPredicate(format: "name_ = %@ and owner_ = %@", obj.name, obj.owner)
                let table = (try? context.fetch(tableRequest))?.first
                // drop table columns
                try? deleteTableColumns(for: table, in: context)
                // drop indexes
                let indexRequest = DBCacheIndex.fetchRequest()
                indexRequest.predicate = NSPredicate(format: "tableName_ = %@ and tableOwner_ = %@", obj.name, obj.owner)
                let indexes = (try? context.fetch(indexRequest)) ?? []
                for index in indexes {
                    try? deleteIndexColumns(for: index, in: context)
                    context.delete(index)
                }
                // drop triggers
                let triggerRequest = DBCacheTrigger.fetchRequest()
                triggerRequest.predicate = NSPredicate(format: "objectName = %@ and objectOwner = %@", obj.name, obj.owner)
                let triggers = (try? context.fetch(triggerRequest)) ?? []
                for trigger in triggers {
                    context.delete(trigger)
                }
                // drop table object
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
            case .unknown:
                break
            default:
                break
        }
        // drop cache object
        context.delete(obj)
        log.cache.debug("exiting from \(#function, privacy: .public)")
    }
    
    func dropManagedObject(_ obj: NSManagedObject?, with context: NSManagedObjectContext) {
        guard let obj else { return }
        context.delete(obj)
    }
    
    func processTriggers(_ objs: [OracleObject], context: NSManagedObjectContext) {
        log.cache.debug("in \(#function, privacy: .public)")
        guard objs.count > 0 else { return }
        guard objs.count < 1000 else { log.cache.error("Unexpected obj count: \(objs.count, privacy: .public)"); fatalError("Unexpected obj count: \(objs.count)") }
        var sql = "select owner, trigger_name, trigger_type, triggering_event, table_owner, base_object_type, table_name, column_name, referencing_names, when_clause, status, description, action_type, trigger_body, crossedition, before_statement, before_row, after_row, after_statement, instead_of_row, fire_once from dba_triggers where owner in ($OWNERS$) and trigger_name in ($NAMES$)"
        guard let conn = pool?.getConnection(tag: "cache", autoCommit: false) else {log.cache.error("could not get a connection"); return }
        defer { pool?.returnConnection(conn: conn) }
        let owners = objs.map { $0.owner }.unique()
        let names = objs.map { $0.name }.unique()
        // build bind var placeholders
        // list of owners
        var paramOwners: [String: BindVar] = [:]
        paramOwners.reserveCapacity(owners.count)
        paramOwners = owners.enumerated().reduce([String: BindVar]()) { (dict, elem) in
            var dict = dict
            dict[":o\(elem.offset)"] = BindVar(elem.element)
            return dict
        }
        // list of names
        var paramNames: [String: BindVar] = [:]
        paramNames.reserveCapacity(names.count)
        paramNames = names.enumerated().reduce([String: BindVar]()) { (dict, elem) in
            var dict = dict
            dict[":n\(elem.offset)"] = BindVar(elem.element)
            return dict
        }
        // put it all together
        let params = paramOwners.merging(paramNames) { (current, _) in current }
        let ownerString = paramOwners.keys.joined(separator: ",")
        let nameString = paramNames.keys.joined(separator: ",")
        sql = sql.replacingOccurrences(of: "$OWNERS$", with: ownerString)
        sql = sql.replacingOccurrences(of: "$NAMES$", with: nameString)
        // execute SQL
        log.cache.debug("in \(#function, privacy: .public), executing SQL: \(sql, privacy: .public) with binds: \(params, privacy: .public)")
        let cur = try? conn.cursor()
        do { try cur?.execute(sql, params: params, prefetchSize: 50000) }
        catch { log.cache.error("\(error.localizedDescription)") }
        // scroll through results and update local cache
        let request = DBCacheTrigger.fetchRequest()
        while let row = cur?.nextSwifty() {
            let owner = (row["OWNER"]!.string)!
            let name = (row["TRIGGER_NAME"]!.string)!
            let type = (row["TRIGGER_TYPE"]!.string)!
            let event = (row["TRIGGERING_EVENT"]!.string)!
            let objectOwner = row["TABLE_OWNER"]!.string
            let objectType = (row["BASE_OBJECT_TYPE"]!.string)!
            let objectName = row["TABLE_NAME"]!.string
            let columnName = row["COLUMN_NAME"]!.string
            let referencingNames = (row["REFERENCING_NAMES"]!.string)!
            let whenClause = row["WHEN_CLAUSE"]!.string
            let isEnabled = row["STATUS"]!.string == "ENABLED"
            let description = row["DESCRIPTION"]!.string
            let actionType = (row["ACTION_TYPE"]!.string)!
            let body = row["TRIGGER_BODY"]!.string
            let isCrossEdition = row["CROSSEDITION"]!.string == "YES"
            let isBeforeStatement = row["BEFORE_STATEMENT"]!.string == "YES"
            let isBeforeRow = row["BEFORE_ROW"]!.string == "YES"
            let isAfterStatement = row["AFTER_STATEMENT"]!.string == "YES"
            let isAfterRow = row["AFTER_ROW"]!.string == "YES"
            let isInsteadOfRow = row["INSTEAD_OF_ROW"]!.string == "YES"
            let isFireOnce = row["FIRE_ONCE"]!.string == "YES"
            // see if the object is already in cache
            request.predicate = NSPredicate(format: "name_ = %@ and owner_ = %@", name, owner)
            let results = (try? context.fetch(request)) ?? []
            if let obj = results.first {
                log.cache.debug("trigger found in cache: \(owner, privacy: .public).\(name, privacy: .public)")
                obj.type = type
                obj.event = event
                obj.objectOwner = objectOwner
                obj.objectType = objectType
                obj.objectName = objectName
                obj.columnName = columnName
                obj.referencingNames = referencingNames
                obj.whenClause = whenClause
                obj.isEnabled = isEnabled
                obj.descr = description
                obj.actionType = actionType
                obj.body = body
                obj.isCrossEdition = isCrossEdition
                obj.isBeforeStatement = isBeforeStatement
                obj.isBeforeRow = isBeforeRow
                obj.isAfterStatement = isAfterStatement
                obj.isAfterRow = isAfterRow
                obj.isInsteadOfRow = isInsteadOfRow
                obj.isFireOnce = isFireOnce
            } else {
                log.cache.debug("creating a new cache instance for trigger \(owner, privacy: .public).\(name, privacy: .public)")
                let obj = DBCacheTrigger(context: context)
                obj.owner = owner
                obj.name = name
                obj.type = type
                obj.event = event
                obj.objectOwner = objectOwner
                obj.objectType = objectType
                obj.objectName = objectName
                obj.columnName = columnName
                obj.referencingNames = referencingNames
                obj.whenClause = whenClause
                obj.isEnabled = isEnabled
                obj.descr = description
                obj.actionType = actionType
                obj.body = body
                obj.isCrossEdition = isCrossEdition
                obj.isBeforeStatement = isBeforeStatement
                obj.isBeforeRow = isBeforeRow
                obj.isAfterStatement = isAfterStatement
                obj.isAfterRow = isAfterRow
                obj.isInsteadOfRow = isInsteadOfRow
                obj.isFireOnce = isFireOnce
            }
        }
        log.cache.debug("exiting from \(#function, privacy: .public)")
    }
    
    func getSource(dbObject: DBCacheObject) async -> String {
        var text = ""
//        try? await Task.sleep(nanoseconds: 3_000_000_000)
        switch OracleObjectType(rawValue: dbObject.type) ?? .unknown {
            case .package, .type:
                await self.persistenceController.container.performBackgroundTask { (context) in
                    let request = DBCacheSource.fetchRequest()
                    request.predicate = NSPredicate(format: "name_ = %@ and owner_ = %@", dbObject.name, dbObject.owner)
                    let results = (try? context.fetch(request)) ?? []
                    if let obj = results.first {
                        text = (obj.textSpec ?? "") + "\n\n\n" + (obj.textBody ?? "")
                    }
                }
            case .view:
                await self.persistenceController.container.performBackgroundTask { (context) in
                    let request = DBCacheTable.fetchRequest()
                    request.predicate = NSPredicate(format: "name_ = %@ and owner_ = %@", dbObject.name, dbObject.owner)
                    let results = (try? context.fetch(request)) ?? []
                    if let obj = results.first {
                        text = obj.sqltext ?? ""
                    }
                }
            default:
                text = "to be developed"
        }
        return text
    }
    
    func editSource(dbObject: DBCacheObject) async -> URL? {
        let text = await getSource(dbObject: dbObject)
        // create a new document, copy properties from the current one
        var newModel = MainModel(text: text)
        newModel.connectionDetails = self.connDetails
        // connect automatically?
//        newModel.autoConnect = true
        // save a temp file
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let temporaryFilename = "\(UUID().uuidString).macintora"
        let temporaryFileURL = temporaryDirectoryURL.appendingPathComponent(temporaryFilename)
        log.debug("temp file path: \(temporaryFileURL.path, privacy: .public)")
        
        do {
            let data = try JSONEncoder().encode(newModel)
            if (FileManager.default.createFile(atPath: temporaryFileURL.path, contents: data, attributes: nil)) {
                log.debug("File created successfully.")
            } else {
                log.error("File not created - \(temporaryFileURL.path, privacy: .public)")
                return nil
            }
        } catch {
            log.error("File write failed: \(error.localizedDescription, privacy: .public), \(temporaryFileURL.path, privacy: .public)")
            return nil
        }
        return temporaryFileURL
    }
    
    func connectSvc() throws {
        log.cache.debug("Attempting to create a service connection pool")
        if self.isConnected == .connected  { return }
        let oracleService = OracleService(from_string: connDetails.tns)
        pool = try ConnectionPool(service: oracleService, user: connDetails.username, pwd: connDetails.password, minConn: 0, maxConn: cacheUpdateSessionLimit, poolType: .Session, isSysDBA: connDetails.connectionRole == .sysDBA)
        pool?.timeout = 5
        self.isConnected = .connected
        log.cache.debug("Connection pool created")
    }
    
    func disconnectSvc() {
        log.cache.debug("Attempting to disconnect the service connection pool")
        guard let pool = pool else {
            log.cache.error("connection pool doesn't exist")
            return
        }
        pool.close()
        self.isConnected = .disconnected
        log.cache.debug("Connection pool closed")
    }
    
    func updateConnDatabase() async {
        log.cache.debug("in \(#function, privacy: .public)")
        var dbid: Int64
        let context = persistenceController.container.newBackgroundContext()
        let request = ConnDatabase.fetchRequest(tns: connDetails.tns)
        let dbs = (try? context.fetch(request)) ?? []
        let localDbVersionFull: String
        let localDbVersionMajor: Int
        let localLastUpdate: Date?
        do { (localDbVersionFull, localDbVersionMajor) = try getDBVersion() } catch { log.cache.error("Could not get DB version, \(error.localizedDescription, privacy: .public)"); return }
        do { dbid = try await Int64(getDBid()) } catch { log.cache.error("Could not get DBID, \(error.localizedDescription, privacy: .public)"); return }
        
        if let db = dbs.first { // an existing db
            log.cache.debug("found databases: \(dbs, privacy: .public)")
            localLastUpdate = db.lastUpdate
            if localDbVersionFull != db.versionFull {
                db.versionFull = localDbVersionFull
                db.versionMajor = Int16(localDbVersionMajor)
            }
            if dbid != db.dbid { // the database for this tns alias has changed, we should rebuild cache
                db.dbid = dbid
                clearCache()
            }
            try? context.save()
            log.cache.debug("ConnDatabase updated: \(db, privacy: .public)")
        } else { // creating a new database entry
            log.cache.debug("did not found databases for tns \(self.connDetails.tns, privacy: .public); creating a new entry")
            let db = ConnDatabase(context: context)
            db.tnsAlias = connDetails.tns
            // set database version
            db.versionFull = localDbVersionFull
            db.versionMajor = Int16(localDbVersionMajor)
            // set DBID
            db.dbid = dbid
            db.objectWillChange.send()
            try? context.save()
            log.cache.debug("new ConnDatabase entry created: \(db, privacy: .public)")
            localLastUpdate = nil
            // update UI
        }
        Task { [self] in await MainActor.run {
            self.dbVersionFull = localDbVersionFull
            self.dbVersionMajor = localDbVersionMajor
            self.lastUpdate = localLastUpdate
        }}
        log.cache.debug("exiting from \(#function, privacy: .public)")
    }
    
    func getDBid() async throws -> Int  {
        log.cache.debug("in \(#function, privacy: .public)")
        var dbid: Int = 0
        let sql = "select dbid, cdb from v$database"
        let sql2 = "select dbid from v$pdbs where name = SYS_CONTEXT('USERENV', 'DB_NAME')"
        guard let conn = pool?.getConnection(tag: "cache", autoCommit: false) else {log.cache.error("could not get a connection"); throw DatabaseErrors.NotConnected}
        defer { pool?.returnConnection(conn: conn) }
        let cur = try? conn.cursor()
        try? cur?.execute(sql)
        if let row = cur?.fetchOneSwifty() {
            dbid = row["DBID"]!.int!
            log.cache.debug("got DBID from v$database: \(dbid); is this a CDB: \(String(describing: row["CDB"]?.string), privacy: .public)")
            if row["CDB"]?.string == "YES" { // this is a CDB
                try? cur?.execute(sql2)
                if let row = cur?.fetchOneSwifty() {
                    dbid = row["DBID"]!.int!
                    log.cache.debug("got row: \(row.fields, privacy: .public)")
                    log.cache.debug("got DBID from v$pdbs: \(dbid)")
                }
            }
        }
        log.cache.debug("exiting from \(#function, privacy: .public)")
        return dbid
    }
    
    func getDBVersion() throws -> (String, Int) {
        log.cache.debug("in \(#function, privacy: .public)")
        var versionFull: String = ""
        var versionMajor: Int = 0
        let sql = "select version_full from product_component_version"
        guard let conn = pool?.getConnection(tag: "cache", autoCommit: false) else {log.cache.error("could not get a connection"); throw DatabaseErrors.NotConnected}
        defer { pool?.returnConnection(conn: conn) }
        let cur = try? conn.cursor()
        try? cur?.execute(sql)
        if let row = cur?.fetchOneSwifty() {
            versionFull = row["VERSION_FULL"]!.string!
            log.cache.debug("got version: \(versionFull, privacy: .public)")
            versionMajor = Int(versionFull.components(separatedBy: ".").first!)!
        }
        log.cache.debug("exiting from \(#function, privacy: .public)")
        return (versionFull, versionMajor)
    }
    
    func deleteAll(from entityName: String) async throws {
        log.cache.debug("Deleting all from \(entityName, privacy: .public)")
        let fetchRequest: NSFetchRequest<NSFetchRequestResult>
        fetchRequest = NSFetchRequest(entityName: entityName)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        deleteRequest.resultType = .resultTypeObjectIDs
        try await self.persistenceController.container.performBackgroundTask { (context) in
            context.automaticallyMergesChangesFromParent = true
            let batchDelete = try context.execute(deleteRequest) as? NSBatchDeleteResult
            guard let deleteResult = batchDelete?.result else { return }
            // sync up with in-memory state
            let changes: [AnyHashable: Any] = [ NSDeletedObjectsKey: deleteResult as! [NSManagedObjectID] ]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
            try? context.save()
        }
        log.cache.debug("Deletion from \(entityName, privacy: .public) finished")
    }
    
    func setLastUpdate(_ value: Date?) {
        log.cache.debug("in \(#function, privacy: .public)")
        let context = persistenceController.container.newBackgroundContext()
        let request = ConnDatabase.fetchRequest(tns: connDetails.tns)
        let dbs = (try? context.fetch(request)) ?? []
        if let db = dbs.first {
            log.cache.debug("found databases: \(dbs, privacy: .public)")
            db.lastUpdate = value
            try? context.save()
            log.cache.debug("ConnDatabase updated: \(db, privacy: .public)")
            // update UI
            Task { [self] in await MainActor.run { self.lastUpdate = value }}
        }
        log.cache.debug("exiting from \(#function, privacy: .public)")
    }
    
    
    
    func reportCacheCounts() -> String {
        log.cache.debug("in \(#function, privacy: .public)")
        let context = persistenceController.container.newBackgroundContext()
        let objFetchRequest = NSFetchRequest<DBCacheObject>(entityName: "DBCacheObject")
        let tableFetchRequest = NSFetchRequest<DBCacheTable>(entityName: "DBCacheTable")
        let indexFetchRequest = NSFetchRequest<DBCacheIndex>(entityName: "DBCacheIndex")
        let tableColFetchRequest = NSFetchRequest<DBCacheTableColumn>(entityName: "DBCacheTableColumn")
        let indexColFetchRequest = NSFetchRequest<DBCacheIndexColumn>(entityName: "DBCacheIndexColumn")
        let sourceFetchRequest = NSFetchRequest<DBCacheSource>(entityName: "DBCacheSource")
        let objCount = try? context.count(for: objFetchRequest)
        let tableCount = try? context.count(for: tableFetchRequest)
        let tableColCount = try? context.count(for: tableColFetchRequest)
        let sourceCount = try? context.count(for: sourceFetchRequest)
        let indexCount = try? context.count(for: indexFetchRequest)
        let indexColCount = try? context.count(for: indexColFetchRequest)
        return "Cache contents:\n Total objects - \(objCount ?? 0)\n tables and views - \(tableCount ?? 0)\n table and view columns - \(tableColCount ?? 0)\n stored code objects: \(sourceCount ?? 0)\n indexes - \(indexCount ?? 0)\n index columns - \(indexColCount ?? 0)"
    }
    
}


