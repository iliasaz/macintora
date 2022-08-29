//
//  DatabaseCache.swift
//  MacOra
//
//  Created by Ilia on 12/4/21.
//

import Foundation
import SwiftUI
import SwiftOracle
import CoreData

extension NSManagedObjectContext {
    public func executeAndMergeChanges(using batchInsertRequest: NSBatchInsertRequest) throws {
        batchInsertRequest.resultType = .objectIDs
        let result = try execute(batchInsertRequest) as! NSBatchInsertResult
        let changes: [AnyHashable: Any] = [NSInsertedObjectsKey: result.result as? [NSManagedObjectID] ?? []]
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self])
    }
}

public class DBCache: ObservableObject {
    private(set) var pool: ConnectionPool? // service connections
    @Published var persistentController: PersistenceController
    var connDetails: ConnectionDetails
    var dbVersionMajor: Int?
    @Published var dbVersionFull: String?
    @Published var lastUpdate: Date?
    let dateFormatter: DateFormatter = DateFormatter()
    
    var lastUpdatedStr: String {
        guard let lst = lastUpdate else { return "(never)" }
        dateFormatter.calendar = Calendar(identifier: .iso8601)
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return dateFormatter.string(from: lst)
    }
    
    static var preview: DBCache = {
        let result = DBCache(connDetails: ConnectionDetails(username: "", password: "", tns: "preview", connectionRole: .regular))
        return result
    }()
    
    init(connDetails: ConnectionDetails, quickFilters: DBObjectBrowserSearchState = DBObjectBrowserSearchState()) {
        self.connDetails = connDetails
        if connDetails.tns == "preview" {
            persistentController = PersistenceController.preview
        } else {
            persistentController = PersistenceController(name: connDetails.tns!)
            setConnDetailsFromCache()
        }
    }
    
    func setConnDetailsFromCache() {
        let context = persistentController.container.newBackgroundContext()
        let request = ConnDatabase.fetchRequest(tns: connDetails.tns!)
        let dbs = (try? context.fetch(request)) ?? []
        if let db = dbs.first {
            log.debug("found databases: \(dbs)")
            let lastUpdate = db.lastUpdate
            let dbVerFull = db.versionFull
            Task { [self] in await MainActor.run {
                self.lastUpdate = lastUpdate
                self.dbVersionFull = dbVerFull
            }}
        }
    }
    
    func setPersistentController(for tns: String) {
        persistentController = PersistenceController(name: tns)
    }
    
    func connectSvc() throws {
        log.debug("Attempting to create a service connection pool")
        let oracleService = OracleService(from_string: connDetails.tns!)
        pool = try ConnectionPool(service: oracleService, user: connDetails.username, pwd: connDetails.password, minConn: Constants.minConnections, maxConn: Constants.maxConnections, poolType: .Session)
        pool!.timeout = 180
        log.debug("Connection pool created")
    }
    
    func disconnectSvc() {
        log.debug("Attempting to disconnect the service connection pool")
        guard let pool = pool else {
            log.error("connection pool doesn't exist")
            return
        }
        pool.close()
        self.pool = nil
        log.debug("Connection pool closed")
    }
    
    public func updateCache() {
        updateConnDatabase()
        let (owners, objects) = updateDBObjects()
//        try? deleteAll(from: "DBCacheTableColumn")
//        try? deleteAll(from: "DBCacheTable")
//        try? deleteAll(from: "DBCacheSource")
//        updateTables(tableOwners: owners, tableNames: objects)
        setLastUpdate(Date())
    }
    
    public func reloadCache() {
        updateConnDatabase()
        Task.detached { [self] in
            do {
                try connectSvc()
            } catch {
                log.error("\(error.localizedDescription)")
            }
            dropCache()
            Task.detached {
                let results = await withTaskGroup(of: Void.self) { taskGroup in
                    taskGroup.addTask { await self.insertMyObjects() }
                    taskGroup.addTask { await self.insertMySynonymPointeeObjects() }
                    taskGroup.addTask { await self.insertMyTables() }
                    taskGroup.addTask { await self.insertMyTableColumns() }
                }
                reportCacheCounts()
                setLastUpdate(Date())
            }
        }
    }
    
    func reportCacheCounts() {
        let context = persistentController.container.newBackgroundContext()
        let objFetchRequest = NSFetchRequest<DBCacheObject>(entityName: "DBCacheObject")
        let tableFetchRequest = NSFetchRequest<DBCacheObject>(entityName: "DBCacheTable")
        let tableColFetchRequest = NSFetchRequest<DBCacheObject>(entityName: "DBCacheTableColumn")
        let objCount = try? context.count(for: objFetchRequest)
        let tableCount = try? context.count(for: tableFetchRequest)
        let tableColCount = try? context.count(for: tableColFetchRequest)
        log.debug("Cache contents: objects - \(objCount ?? 0), tables - \(tableCount ?? 0), columns - \(tableColCount ?? 0)")
    }
    
    func insertObjects(sql: String, context: NSManagedObjectContext) {
        log.debug("in \(#function)")
        guard let conn = pool?.getConnection(tag: "cache", autoCommit: false) else { log.debug("Could not get a connection from the cache pool"); return }
        log.debug("in \(#function), executing SQL: \(sql)")
        let cur = try? conn.cursor()
        try? cur?.execute(sql, prefetchSize: 10000)
        log.debug("finished executing select statement in \(#function)")
        var objects: [[String: Any]] = []
        var iter = 0
        while let row = cur?.nextSwifty() {
            objects.append([
                "owner_":   row["OWNER"]!.string!,
                "name_":    row["OBJECT_NAME"]!.string!,
                "type_":    row["OBJECT_TYPE"]!.string!,
                "lastDDLDate": row["LAST_DDL_TIME"]!.date
            ])
            iter += 1
            if iter%1000 == 0 {
                log.debug("fetched \(iter) db objects")
            }
        }
        log.debug("finished fetching objects from the source database \(self.connDetails.tns ?? "")")
        let request = NSBatchInsertRequest(entityName: "DBCacheObject", objects: objects)
        do {
            try context.executeAndMergeChanges(using: request)
            try context.save()
        } catch {
            log.error("\(error.localizedDescription)")
        }
        log.debug("end \(#function)")
    }
    
    func insertMyObjects() async {
        log.debug("in \(#function)")
        let context = persistentController.container.newBackgroundContext()
        let sql = "select /*+ rule */ user owner, object_name, object_type, last_ddl_time from user_objects"
        insertObjects(sql: sql, context: context)
        log.debug("end \(#function)")
    }
    
    func insertMySynonymPointeeObjects() async {
        log.debug("in \(#function)")
        let context = persistentController.container.newBackgroundContext()
        let sql = """
            with syn as (select /*+ materialize */ * from user_synonyms)
            select /*+ leading (syn, o) use_nl(syn, o) */ syn.table_owner owner, syn.table_name object_name, object_type, last_ddl_time
            from syn, all_objects o
            where o.owner = syn.table_owner and o.object_name = syn.table_name
        """
        insertObjects(sql: sql, context: context)
        log.debug("end \(#function)")
    }
    
    func insertAllObjects() async {
        log.debug("in \(#function)")
        let context = persistentController.container.newBackgroundContext()
        let sql = "select /*+ rule */ owner, object_name, object_type, last_ddl_time from all_objects where object_type in ('TABLE') and owner not like 'CDR_W%'"
        insertObjects(sql: sql, context: context)
        log.debug("end \(#function)")
    }
    
    func insertTables(sql: String, context: NSManagedObjectContext) {
        log.debug("in \(#function)")
        let conn = pool?.getConnection(tag: "cache", autoCommit: false)
        log.debug("in \(#function), executing SQL: \(sql)")
        let cur = try? conn?.cursor()
        do {
            try cur?.execute(sql, prefetchSize: 10000)
        } catch { log.error("\(error.localizedDescription)") }
        log.debug("finished executing select statement in \(#function)")
        var objects: [[String: Any]] = []
        var iter = 0
        while let row = cur?.nextSwifty() {
            objects.append([
                "owner_":   row["OWNER"]!.string!,
                "name_":    row["TABLE_NAME"]!.string!,
                "numRows":  Int64(row["NUM_ROWS"]!.int ?? 0),
                "lastAnalyzed": row["LAST_ANALYZED"]!.date,
                "isView":   false,
                "partitioned": row["PARTITIONED"]?.string == "YES"
            ])
            iter += 1
            if iter%1000 == 0 {
                log.debug("fetched \(iter) tables")
            }
        }
        log.debug("finished fetching tables from the source database \(self.connDetails.tns ?? "")")
        let request = NSBatchInsertRequest(entityName: "DBCacheTable", objects: objects)
        do {
            try context.executeAndMergeChanges(using: request)
            try context.save()
        } catch {
            log.error("\(error.localizedDescription)")
        }
        log.debug("end \(#function)")
    }
    
    func insertMyTables() async {
        log.debug("in \(#function)")
        let context = persistentController.container.newBackgroundContext()
        let sql = "select /*+ rule */ user owner, table_name, num_rows, last_analyzed, partitioned from user_tables"
        insertTables(sql: sql, context: context)
        log.debug("end \(#function)")
    }
    
    func insertAllTables() async {
        log.debug("in \(#function)")
        let context = persistentController.container.newBackgroundContext()
        let sql = "select /*+ rule */ owner, table_name, num_rows, last_analyzed, partitioned from all_tables where owner not like 'CDR_W%'"
        insertTables(sql: sql, context: context)
        log.debug("end \(#function)")
    }
    
    func insertTableColumns(sql: String, context: NSManagedObjectContext) {
        log.debug("in \(#function)")
        let conn = pool?.getConnection(tag: "cache", autoCommit: false)
        log.debug("in \(#function), executing SQL: \(sql)")
        let cur = try? conn?.cursor()
        do {
            try cur?.execute(sql, prefetchSize: 50000)
        } catch { log.error("\(error.localizedDescription)") }
        log.debug("finished executing select statement in \(#function)")
        var objects: [[String: Any]] = []
        var iter = 0
        while let row = cur?.nextSwifty() {
            objects.append([
                "owner_":       row["OWNER"]?.string!,
                "tableName_":   row["TABLE_NAME"]!.string!,
                "isNullable":   row["NULLABLE"]!.string == "Y",
                "isHidden":     row["HIDDEN_COLUMN"]!.string == "YES",
                "isSysGen":     row["USER_GENERATED"]!.string == "NO",
                "isVirtual":    row["VIRTUAL_COLUMN"]!.string == "YES",
                "isIdentity":   row["IDENTITY_COLUMN"]!.string == "YES",
                "dataType_":    row["DATA_TYPE"]!.string,
                "dataTypeMod_": row["DATA_TYPE_MOD"]!.string,
                "dataTypeOwner_": row["DATA_TYPE_OWNER"]!.string,
                "columnID":     Int16(row["COLUMN_ID"]!.int ?? 0),
                "columnName_":  row["COLUMN_NAME"]!.string,
                "length":       Int32(row["DATA_LENGTH"]!.int!),
                "defaultValue": row["DATA_DEFAULT"]!.string,
                "numNulls":     Int64(row["NUM_NULLS"]!.int ?? 0),
                "numDistinct":  Int64(row["NUM_DISTINCT"]!.int ?? 0),
                "precision":    Int16(row["DATA_PRECISION"]!.int ?? 0),
                "scale":        Int16(row["DATA_SCALE"]!.int ?? 0)
            ])
            iter += 1
            if iter%1000 == 0 {
                log.debug("fetched \(iter) columns")
            }
        }
        log.debug("finished fetching columns from the source database \(self.connDetails.tns ?? "")")
        let request = NSBatchInsertRequest(entityName: "DBCacheTableColumn", objects: objects)
        do {
            try context.executeAndMergeChanges(using: request)
            try context.save()
        } catch {
            log.error("\(error.localizedDescription)")
        }
        log.debug("end \(#function)")
    }
    
    func insertMyTableColumns() async {
        log.debug("in \(#function)")
        let context = persistentController.container.newBackgroundContext()
        let sql = "select user owner, table_name, column_name, data_type, data_type_mod, data_type_owner, data_precision, data_scale, data_length, nullable, column_id, data_default, num_distinct, num_nulls, identity_column, hidden_column, virtual_column, user_generated from user_tab_cols"
        insertTableColumns(sql: sql, context: context)
        log.debug("end \(#function)")
    }
    
    func insertAllTableColumns() async {
        log.debug("in \(#function)")
        let context = persistentController.container.newBackgroundContext()
        let sql = "select owner, table_name, column_name, data_type, data_type_mod, data_type_owner, data_precision, data_scale, data_length, nullable, column_id, data_default, num_distinct, num_nulls, identity_column, hidden_column, virtual_column, user_generated from all_tab_cols where owner not like 'CDR_W%'"
        insertTableColumns(sql: sql, context: context)
        log.debug("end \(#function)")
    }
    
    func updateTables(tableOwners: [String], tableNames: [String]) {
        log.debug("in \(#function)")
        if tableNames.count == 0 { log.debug("nothing to update, exiting"); return }
        let context = persistentController.container.newBackgroundContext()
        let sql = "select owner, table_name, num_rows, last_analyzed, partitioned from all_tables where owner = :owner and table_name = :tableName"
        let conn = pool?.getConnection(tag: "cache", autoCommit: false)
        log.debug("in \(#function), executing SQL: \(sql)")
        let cur = try? conn?.cursor()
        for (i, tab) in tableNames.enumerated() {
            log.debug("selecting columns from source database for \(tableOwners[i]).\(tableNames[i])")
            do {
                try cur?.execute(sql, params: [":owner": BindVar(tableOwners[i]), ":tableName": BindVar(tableNames[i])], prefetchSize: 100)
            } catch { log.error("\(error.localizedDescription)") }
            let request = DBCacheTable.fetchRequest()
            while let row = cur?.nextSwifty() {
                let tableName = (row["TABLE_NAME"]?.string)!
                let tableOwner = (row["OWNER"]?.string)!
                let numRows = (row["NUM_ROWS"]?.int) ?? 0
                let lastAnalyzed = row["LAST_ANALYZED"]?.date
                // see if the object is already in cache
                request.predicate = NSPredicate(format: "name_ = %@ and owner_ = %@", tableName, tableOwner)
                let results = (try? context.fetch(request)) ?? []
                if let obj = results.first {
                    log.debug("Table found in cache: \(tableOwners[i]).\(tableNames[i])")
                    obj.numRows = Int64(numRows)
                    obj.lastAnalyzed = lastAnalyzed
                    obj.partitioned = ( row["PARTITIONED"]?.string == "YES" )
                    // now drop columns, they will be re-populated
                    try? deleteColumns(for: obj, in: context)
                    populateTableColumns(for: obj, in: context, using: conn!)
                } else {
                    log.debug("creating a new cache instance for table \(tableOwners[i]).\(tableNames[i])")
                    let obj = DBCacheTable(context: context)
                    obj.owner_ = tableOwner
                    obj.name_ = tableName
                    obj.isView = false
                    obj.numRows = Int64(numRows)
                    obj.lastAnalyzed = row["LAST_ANALYZED"]?.date
                    obj.partitioned = ( row["PARTITIONED"]?.string == "YES" )
                    populateTableColumns(for: obj, in: context, using: conn!)
                }
            }
        }
        log.debug("\(#function) update complete, table count: \(tableNames.count)")
        try? context.save()
        log.debug("saved")
    }
    
    func populateTableColumns(for table: DBCacheTable, in context: NSManagedObjectContext, using conn: PooledConnection) {
        log.debug("populating columns for table \(table.owner).\(table.name)")
        let sql = "select owner, table_name, column_name, data_type, data_precision, data_scale, data_length, nullable, column_id, data_default, num_distinct, num_buckets, identity_column from all_tab_columns where owner = :owner and table_name = :tableName"
        let cur = try? conn.cursor()
        try? cur?.execute(sql, params: [":owner": BindVar(table.owner), ":tableName": BindVar(table.name)])
        var cnt = 0
        while let row = cur?.nextSwifty() {
            let col = DBCacheTableColumn(context: context)
            col.isNullable = row["NULLABLE"]!.string == "Y"
            col.dataType_ = row["DATA_TYPE"]!.string
            col.columnID = Int16(row["COLUMN_ID"]!.int!)
            col.columnName_ = row["COLUMN_NAME"]!.string
            col.length = Int32(row["DATA_LENGTH"]!.int!)
            col.defaultValue = row["DATA_DEFAULT"]!.string
            col.isIdentity = row["IDENTITY_COLUMN"]!.string == "YES"
            col.numNulls = Int64(row["NUM_NULLS"]!.int ?? 0)
            col.numDistinct = Int64(row["NUM_DISTINCT"]!.int ?? 0)
            col.precision = Int16(row["DATA_PRECISION"]!.int ?? 0)
            col.scale = Int16(row["DATA_SCALE"]!.int ?? 0)
            col.owner_ = table.owner_
            col.tableName_ = table.name_
            cnt += 1
        }
        log.debug("added \(cnt) columns in table \(table.owner).\(table.name)")
    }
    
    func updateDBObjects() -> ([String], [String]) {
        let context = persistentController.container.newBackgroundContext()
        // now update objects in cache
//        let sql = "select owner, object_name, object_type, last_ddl_time from all_objects where object_type in ('TABLE','VIEW','PACKAGE','PROCEDURE','FUNCTION') and last_ddl_time > :lastUpdate and owner not like 'CDR_W%'"
        let sql = "select owner, object_name, object_type, last_ddl_time from all_objects where object_type in ('TABLE') and last_ddl_time > :lastUpdate and owner not like 'CDR_W%'"
        let conn = pool?.getConnection(tag: "cache", autoCommit: false)
        log.debug("in \(#function), executing SQL: \(sql) with lastUpdate: \(String(describing: self.lastUpdate))")
        let cur = try? conn?.cursor()
        try? cur?.execute(sql, params: [":lastUpdate": BindVar(self.lastUpdate ?? Constants.minDate)], prefetchSize: 5000)
        log.debug("finished select from the source database \(self.connDetails.tns ?? "")")
        log.debug("fetching")
        let request = DBCacheObject.fetchRequest()
        // TODO: should consider array processing here
        var objNames = [String](), objTypes = [String](), objOwners = [String]()
        var iter = 0
        while let row = cur?.nextSwifty() {
            // see if the object is already in cache
            let objName = (row["OBJECT_NAME"]?.string)!
            let objOwner = (row["OWNER"]?.string)!
            let objType =  (row["OBJECT_TYPE"]?.string)!
            // save for future use
            objNames.append(objName)
            objTypes.append(objType)
            objOwners.append(objOwner)
            log.debug("processing \(objOwner).\(objName)")
            request.predicate = NSPredicate(format: "name_ = %@ and owner_ = %@ and type_ = %@ ", objName, objOwner, objType)
            let results = (try? context.fetch(request)) ?? []
            if let obj = results.first {
                log.debug("updating existing db object \(objOwner).\(obj.name)")
                obj.owner = objOwner
                obj.name = objName
                obj.type = objType
                obj.lastDDLDate = row["LAST_DDL_TIME"]?.date
            } else {
                log.debug("creating a new db object \(objOwner).\(objName)")
                let obj = DBCacheObject(context: context)
                obj.owner = objOwner
                obj.name = objName
                obj.type = objType
                obj.lastDDLDate = row["LAST_DDL_TIME"]?.date
            }
            iter += 1
            if iter%1000 == 0 {
                log.debug("updated \(iter) db objects")
            }
        }
        log.debug("\(#function) update complete, object count: \(objNames.count)")
        try? context.save()
        log.debug("\(#function) DBObjects saved")
        return (objOwners, objNames)
    }
    
    func setLastUpdate(_ value: Date?) {
        let context = persistentController.container.newBackgroundContext()
        let request = ConnDatabase.fetchRequest(tns: connDetails.tns!)
        let dbs = (try? context.fetch(request)) ?? []
        if let db = dbs.first {
            log.debug("found databases: \(dbs)")
            db.lastUpdate = value
            try? context.save()
            log.debug("ConnDatabase updated: \(db)")
            // update UI
            Task { [self] in await MainActor.run { self.lastUpdate = db.lastUpdate }}
        }
    }
    
    func updateConnDatabase() {
        var dbid: Int64
        let context = persistentController.container.newBackgroundContext()
        let request = ConnDatabase.fetchRequest(tns: connDetails.tns!)
        let dbs = (try? context.fetch(request)) ?? []
        let localDbVersionFull: String
        let localDbVersionMajor: Int
        let localLastUpdate: Date
        do { (localDbVersionFull, localDbVersionMajor) = try populateDBVersion() } catch { log.error("Could not get DB version, \(error.localizedDescription)"); return }
        do { dbid = try Int64(populateDBid()) } catch { log.error("Could not get DBID, \(error.localizedDescription)"); return }
        
        if let db = dbs.first { // an existing db
            log.debug("found databases: \(dbs)")
            localLastUpdate = db.lastUpdate ?? Constants.minDate
            if localDbVersionFull != db.versionFull {
                db.versionFull = localDbVersionFull
                db.versionMajor = Int16(localDbVersionMajor)
            }
            if dbid != db.dbid { // the database for this tns alias has changed, we should rebuild cache
                db.dbid = dbid
                dropCache()
            }
            try? context.save()
            log.debug("ConnDatabase updated: \(db)")
        } else { // creating a new database entry
            log.debug("did not found databases for tns \(self.connDetails.tns ?? ""); creating a new entry")
            let db = ConnDatabase(context: context)
            db.tnsAlias = connDetails.tns!
            // set database version
            db.versionFull = localDbVersionFull
            db.versionMajor = Int16(localDbVersionMajor)
            // set DBID
            db.dbid = dbid
            db.objectWillChange.send()
            try? context.save()
            log.debug("new ConnDatabase entry created: \(db)")
            localLastUpdate = Constants.minDate
            // update UI
        }
        Task { [self] in await MainActor.run {
            self.dbVersionFull = localDbVersionFull
            self.dbVersionMajor = localDbVersionMajor
            self.lastUpdate = localLastUpdate
        }}
    }
    
    func populateDBid() throws -> Int  {
        var dbid: Int = 0
        log.debug("in \(#function)")
        let sql = "select dbid, cdb from v$database"
        let sql2 = "select dbid from v$pdbs where name = SYS_CONTEXT('USERENV', 'DB_NAME')"
        guard let conn = pool?.getConnection(tag: "cache", autoCommit: false) else { throw DatabaseErrors.NotConnected }
        let cur = try? conn.cursor()
        try? cur?.execute(sql)
        if let row = cur?.fetchOneSwifty() {
            dbid = row["DBID"]!.int!
            log.debug("got DBID from v$database: \(dbid); is this a CDB: \(String(describing: row["CDB"]?.string))")
            if row["CDB"]?.string == "YES" { // this is a CDB
                try? cur?.execute(sql2)
                if let row = cur?.fetchOneSwifty() {
                    dbid = row["DBID"]!.int!
                    log.debug("got row: \(row.fields)")
                    log.debug("got DBID from v$pdbs: \(dbid)")
                }
            }
        }
        log.debug("exiting \(#function)")
        return dbid
    }
    
    func populateDBVersion() throws -> (String, Int) {
        var versionFull: String = ""
        var versionMajor: Int = 0
        log.debug("in \(#function)")
        let sql = "select version_full from product_component_version"
        guard let conn = pool?.getConnection(tag: "cache", autoCommit: false) else { throw DatabaseErrors.NotConnected }
        let cur = try? conn.cursor()
        try? cur?.execute(sql)
        if let row = cur?.fetchOneSwifty() {
            versionFull = row["VERSION_FULL"]!.string!
            log.debug("got version: \(versionFull)")
            versionMajor = Int(versionFull.components(separatedBy: ".").first!)!
        }
        log.debug("exiting \(#function)")
        return (versionFull, versionMajor)
    }
    
    func deleteAll(from entityName: String) throws {
        log.debug("Deleting all from \(entityName)")
        let fetchRequest: NSFetchRequest<NSFetchRequestResult>
        fetchRequest = NSFetchRequest(entityName: entityName)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        deleteRequest.resultType = .resultTypeObjectIDs
        let context = persistentController.container.newBackgroundContext()
        let batchDelete = try context.execute(deleteRequest) as? NSBatchDeleteResult
        guard let deleteResult = batchDelete?.result else { return }
        // sync up with in-memory state
        let changes: [AnyHashable: Any] = [ NSDeletedObjectsKey: deleteResult as! [NSManagedObjectID] ]
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        try? context.save()
        log.debug("Deletion from \(entityName) finished")
    }
    
    func deleteColumns(for table: DBCacheTable, in context: NSManagedObjectContext) throws {
        log.debug("\(#function) Deleting columns from \(table.owner).\(table.name)")
        let fetchRequest: NSFetchRequest<NSFetchRequestResult>
        fetchRequest = NSFetchRequest(entityName: "DBCacheTableColumn")
        fetchRequest.predicate = NSPredicate(format: "table = %@", table)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        deleteRequest.resultType = .resultTypeObjectIDs
        let batchDelete = try context.execute(deleteRequest) as? NSBatchDeleteResult
        guard let deleteResult = batchDelete?.result else { return }
        // sync up with in-memory state
        let changes: [AnyHashable: Any] = [ NSDeletedObjectsKey: deleteResult as! [NSManagedObjectID] ]
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        guard let deleteResult = batchDelete?.result else { return }
//        log.debug("Deletion of columns for \(table.owner).\(table.name) finished with result: \(deleteResult)")
    }
    
    func dropCache() {
        do {
            try deleteAll(from: "DBCacheObject")
            try deleteAll(from: "DBCacheTableColumn")
            try deleteAll(from: "DBCacheTable")
            try deleteAll(from: "DBCacheSource")
        } catch {
            log.error("\(error.localizedDescription)")
        }
        setLastUpdate(nil)
    }

}


