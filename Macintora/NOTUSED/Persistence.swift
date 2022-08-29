//
//  Persistence.swift
//  MacOraCoreData
//
//  Created by Ilia on 11/22/21.
//

import CoreData

public extension NSManagedObject {

    convenience init(context: NSManagedObjectContext) {
        let name = String(describing: type(of: self))
        let entity = NSEntityDescription.entity(forEntityName: name, in: context)!
        self.init(entity: entity, insertInto: context)
    }

}

//let dataModel = NSManagedObjectModel(contentsOf: URL(fileURLWithPath: "file:///DatabaseCacheModel.xcdatamodeld/DatabaseCacheModel.xcdatamodel"))!

// initialized data model
let modelURL = Bundle.main.url(forResource: "DatabaseCacheModel", withExtension: "momd")!
let dataModel = NSManagedObjectModel(contentsOf: modelURL)!


struct PersistenceController {
    
    static var preview: PersistenceController = {
        log.debug("Creating a preview context")
        let result = PersistenceController(inMemory: true, name: "preview")
        let viewContext = result.container.viewContext
        let db = DBCacheObject(context: viewContext)
        for i in 0..<10 {
            let dbObject = DBCacheObject(context: viewContext)
            dbObject.name_ = "Table \(i)"
            dbObject.type_ = "TABLE"
            dbObject.owner_ = "TEST_USER"
            dbObject.lastDDLDate = Date()
        }
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        log.debug("Finished creating preview context")
        return result
    }()
    
    let container: NSPersistentContainer
    
    init(inMemory: Bool = false, name: String = "preview") {
        
        container = NSPersistentContainer(name: name, managedObjectModel: dataModel)
        log.debug("container created")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.name = name
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            log.debug("in loadPersistentStores, error: \(error?.localizedDescription ?? "no message"), storeDescription: \(storeDescription.debugDescription )")
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
