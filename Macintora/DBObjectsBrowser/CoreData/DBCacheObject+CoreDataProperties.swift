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
    
    public class func fetchRequest(limit: Int) -> NSFetchRequest<DBCacheObject> {
        let request = DBCacheObject.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "owner_", ascending: true), NSSortDescriptor(key: "type_", ascending: true), NSSortDescriptor(key: "name_", ascending: true)]
        request.fetchLimit = limit
        return request
    }
}
