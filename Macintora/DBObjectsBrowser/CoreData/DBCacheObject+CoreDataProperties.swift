//
//  DBCacheObject+CoreDataProperties.swift
//  
//
//  Created by Ilia on 1/6/22.
//
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData

extension DBCacheObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<DBCacheObject> {
        return NSFetchRequest<DBCacheObject>(entityName: "DBCacheObject")
    }

    @NSManaged public var lastDDLDate: Date?
    @NSManaged public var name_: String?
    @NSManaged public var owner_: String?
    @NSManaged public var type_: String?
    @NSManaged public var createDate: Date?
    @NSManaged public var editionName: String?
    @NSManaged public var isEditionable: Bool
    @NSManaged public var isValid: Bool
    @NSManaged public var objectId: Int
}

extension DBCacheObject : Identifiable {

}

extension DBCacheObject {
    var name: String {
        get { self.name_ ?? "(null)" }
        set { self.name_ = newValue }
    }
    
    var type: String {
        get { self.type_ ?? "(null)"  }
        set { self.type_ = newValue }
    }
    
    var owner: String {
        get { self.owner_ ?? "(null)"  }
        set { self.owner_ = newValue }
    }
    
    public class func fetchRequest(limit: Int, predicate: NSPredicate? = nil) -> NSFetchRequest<DBCacheObject> {
        let request = DBCacheObject.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "owner_", ascending: true), NSSortDescriptor(key: "type_", ascending: true), NSSortDescriptor(key: "name_", ascending: true)]
        request.fetchLimit = limit
        if let predicate = predicate {
            request.predicate = predicate
        }
        return request
    }
}

extension DBCacheObject {
    static var exampleTrigger: DBCacheObject {
        let context = PersistenceController.preview.container.viewContext
        let request = DBCacheObject.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "type_ = %@", "TRIGGER")
        let results = try? context.fetch(request)
        return (results?.first!)!
    }
    
    static var exampleTable: DBCacheObject {
        let context = PersistenceController.preview.container.viewContext
        let request = DBCacheObject.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "type_ = %@", "TABLE")
        let results = try? context.fetch(request)
        return (results?.first!)!
    }
    
    static var examplePackage: DBCacheObject {
        let context = PersistenceController.preview.container.viewContext
        let request = DBCacheObject.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "type_ = %@", "PACKAGE")
        let results = try? context.fetch(request)
        return (results?.first!)!
    }
}
