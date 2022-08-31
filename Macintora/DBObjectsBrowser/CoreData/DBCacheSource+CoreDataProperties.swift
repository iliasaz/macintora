//
//  DBCacheSource+CoreDataProperties.swift
//  
//
//  Created by Ilia on 1/5/22.
//
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData


extension DBCacheSource {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<DBCacheSource> {
        return NSFetchRequest<DBCacheSource>(entityName: "DBCacheSource")
    }

    @NSManaged public var name_: String?
    @NSManaged public var owner_: String?
    @NSManaged public var textSpec: String?
    @NSManaged public var textBody: String?
//    @NSManaged public var type_: String?

}

extension DBCacheSource : Identifiable {
    
}

extension DBCacheSource {
    var name: String {
        get { self.name_ ?? "(null)" }
        set { self.name_ = newValue }
    }
    
    var owner: String {
        get { self.owner_ ?? "(null)"  }
        set { self.owner_ = newValue }
    }
    
//    var type: String {
//        get { self.type_ ?? "(null)"  }
//        set { self.type_ = newValue }
//    }
}
