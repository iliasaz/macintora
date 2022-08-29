//
//  DBCacheTable+CoreDataProperties.swift
//  
//
//  Created by Ilia on 1/5/22.
//
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData


extension DBCacheTable {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<DBCacheTable> {
        return NSFetchRequest<DBCacheTable>(entityName: "DBCacheTable")
    }
    @NSManaged public var isView: Bool
    @NSManaged public var isEditioning: Bool
    @NSManaged public var isReadOnly: Bool
    @NSManaged public var sqltext: String?
    @NSManaged public var lastAnalyzed: Date?
    @NSManaged public var name_: String?
    @NSManaged public var numRows: Int64
    @NSManaged public var owner_: String?
    @NSManaged public var isPartitioned: Bool
}


extension DBCacheTable : Identifiable {

}

extension DBCacheTable {
    var name: String {
        get { self.name_ ?? "(null)" }
        set { self.name_ = newValue }
    }
    
    var owner: String {
        get { self.owner_ ?? "(null)"  }
        set { self.owner_ = newValue }
    }
}
