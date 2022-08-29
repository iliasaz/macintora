//
//  DBCacheIndexColumn+CoreDataProperties.swift
//  DBObjectsBrowser
//
//  Created by Ilia on 6/20/22.
//

import Foundation
import CoreData

extension DBCacheIndexColumn {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<DBCacheIndexColumn> {
        return NSFetchRequest<DBCacheIndexColumn>(entityName: "DBCacheIndexColumn")
    }
    @NSManaged public var columnName_: String?
    @NSManaged public var indexName_: String?
    @NSManaged public var isDescending: Bool
    @NSManaged public var length: Int32
    @NSManaged public var owner_: String?
    @NSManaged public var position: Int16
}


extension DBCacheIndexColumn : Identifiable {
    
}

extension DBCacheIndexColumn {
    @objc var columnName: String {
        get { self.columnName_ ?? "(null)" }
        set { self.columnName_ = newValue }
    }
    
    @objc var owner: String {
        get { self.owner_ ?? "(null)"  }
        set { self.owner_ = newValue }
    }
    
    @objc var indexName: String {
        get { self.indexName_ ?? "(null)" }
        set { self.indexName_ = newValue }
    }
}
