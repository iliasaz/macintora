//
//  Persistence.swift
//  DBObjectsBrowser
//
//  Created by Ilia on 1/1/22.
//

import Foundation
import CoreData
import os

//public extension NSManagedObject {
//
//    convenience init(context: NSManagedObjectContext) {
//        let name = String(describing: type(of: self))
//        let entity = NSEntityDescription.entity(forEntityName: name, in: context)!
//        self.init(entity: entity, insertInto: context)
//    }
//
//}

// initialized data model
let modelURL = Bundle.main.url(forResource: "DatabaseCacheModel", withExtension: "momd")!
let dataModel = NSManagedObjectModel(contentsOf: modelURL)!
//let name = "dmwoac"
let defaultName = "preview"


struct PersistenceController {
    
    var container: NSPersistentContainer
    
    init(name: String) {
        container = NSPersistentContainer(name: name, managedObjectModel: dataModel)
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.name = name
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            log.cache.debug("in loadPersistentStores, storeDescription: \(storeDescription.debugDescription )")
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                
                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            } else {
//                storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
//                storeDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            }
        })
    }

    init(inMemory: Bool = false) {
//        container = NSPersistentContainer(name: "DBObjectsBrowser")
        container = NSPersistentContainer(name: defaultName, managedObjectModel: dataModel)
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.name = defaultName
//        log.cache.debug("persistentStoreDescriptions: \(container.persistentStoreDescriptions)")
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            log.cache.debug("in loadPersistentStores, storeDescription: \(storeDescription.debugDescription )")
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                Typical reasons for an error here include:
                * The parent directory does not exist, cannot be created, or disallows writing.
                * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                * The device is out of space.
                * The store could not be migrated to the current model version.
                Check the error message to determine what the actual problem was.
                */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
    }
}
