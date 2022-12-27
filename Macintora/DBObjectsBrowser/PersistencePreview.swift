//
//  PersistencePreview.swift
//  Macintora
//
//  Created by Ilia Sazonov on 12/14/22.
//

import Foundation
import CoreData

extension PersistenceController {
    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        for _ in 0..<10 {
            let newItem = Item(context: viewContext)
            newItem.timestamp = Date()
        }
        
        let triggerObj = sampleTriggerObj(in: viewContext)
        let trigger = sampleTrigger(in: viewContext)
        
        let tableObj = sampleTableObj(in: viewContext)
        let table = sampleTable(in: viewContext)
        
        let packageObj = samplePackageObj(in: viewContext)
        let package = samplePackage(in: viewContext)
        
        do {
            try viewContext.save()
            debugPrint("created exampleTrigger")
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()
    
    static func sampleTriggerObj(in context: NSManagedObjectContext) -> DBCacheObject {
        let obj = DBCacheObject(context: context)
        obj.owner = "OWNER"
        obj.name = "MYTRIGGER"
        obj.lastDDLDate = Date()
        obj.type = "TRIGGER"
        obj.createDate = Date()
        obj.objectId = 12345
        obj.isValid = true
        obj.isEditionable = true
        obj.editionName = "ORA$BASE"
        return obj
    }
    
    static func sampleTableObj(in context: NSManagedObjectContext) -> DBCacheObject {
        let obj = DBCacheObject(context: context)
        obj.owner = "OWNER"
        obj.name = "MYTABLE"
        obj.lastDDLDate = Date()
        obj.type = "TABLE"
        obj.createDate = Date()
        obj.objectId = 12345
        obj.isValid = true
        obj.isEditionable = false
        obj.editionName = ""
        return obj
    }
    
    static func samplePackageObj(in context: NSManagedObjectContext) -> DBCacheObject {
        let obj = DBCacheObject(context: context)
        obj.owner = "OWNER"
        obj.name = "MY_PACKAGE"
        obj.lastDDLDate = Date()
        obj.type = "PACKAGE"
        obj.createDate = Date()
        obj.objectId = 12345
        obj.isValid = true
        obj.isEditionable = true
        obj.editionName = "ORA$BASE"
        return obj
    }
    
    static func sampleTrigger(in context: NSManagedObjectContext) -> DBCacheTrigger {
        let trigger = DBCacheTrigger(context: context)
        trigger.actionType = "PL/SQL"
        trigger.body = "begin null; end;"
        trigger.columnName = "column A"
        trigger.descr = "no description"
        trigger.event = "INSERT OR UPDATE OR DELETE"
        trigger.isAfterRow = false
        trigger.isAfterStatement = false
        trigger.isBeforeRow = true
        trigger.isBeforeStatement = false
        trigger.isCrossEdition = false
        trigger.isEnabled = true
        trigger.isFireOnce = false
        trigger.isInsteadOfRow = false
        trigger.name = "MYTRIGGER"
        trigger.objectName = "MYTABLE"
        trigger.objectOwner = "OWNER"
        trigger.objectType = "TABLE"
        trigger.owner = "OWNER"
        trigger.referencingNames = "OLD AS OLD NEW AS NEW"
        trigger.type = "BEFORE EACH ROW"
        trigger.whenClause = "When clause"
        return trigger
    }
    
    static func sampleTable(in context: NSManagedObjectContext) -> DBCacheTable {
        let table = DBCacheTable(context: context)
        table.isEditioning = false
        table.isPartitioned = false
        table.isReadOnly = false
        table.isView = false
        table.lastAnalyzed = Date()
        table.name = "MYTABLE"
        table.owner = "OWNER"
        table.numRows = 1000
        table.sqltext = ""
        return table
    }
    
    static func samplePackage(in context: NSManagedObjectContext) -> DBCacheSource {
        let table = DBCacheSource(context: context)
        table.name = "MYTABLE"
        table.owner = "OWNER"
        table.textSpec = "create or replace package my_package as <>"
        table.textBody = "create or replace package my_package body as <>"
        return table
    }
}
