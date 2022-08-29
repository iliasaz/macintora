//
//  DBCacheTableColumn+CoreDataProperties.swift
//  
//
//  Created by Ilia on 1/5/22.
//
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData


extension DBCacheTableColumn {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<DBCacheTableColumn> {
        let request = NSFetchRequest<DBCacheTableColumn>(entityName: "DBCacheTableColumn")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \DBCacheTableColumn.columnID, ascending: true)]
        return request
    }

    @NSManaged public var columnID: NSNumber?
    @NSManaged public var internalColumnID: Int16
    @NSManaged public var columnName_: String?
    @NSManaged public var dataType_: String?
    @NSManaged public var dataTypeMod_: String?
    @NSManaged public var dataTypeOwner_: String?
    @NSManaged public var defaultValue: String?
    @NSManaged public var isHidden: Bool
    @NSManaged public var isIdentity: Bool
    @NSManaged public var isNullable: Bool
    @NSManaged public var isSysGen: Bool
    @NSManaged public var isVirtual: Bool
    @NSManaged public var length: Int32
    @NSManaged public var numDistinct: Int64
    @NSManaged public var numNulls: Int64
    @NSManaged public var owner_: String?
    @NSManaged public var precision: NSNumber?
    @NSManaged public var scale: NSNumber?
    @NSManaged public var tableName_: String?
}

extension DBCacheTableColumn : Identifiable {

}

extension DBCacheTableColumn: NSCopying {
    public func copy(with zone: NSZone? = nil) -> Any {
        return self
    }
}

extension DBCacheTableColumn {
    var tableName: String {
        get { self.tableName_ ?? "(null)" }
        set { self.tableName_ = newValue }
    }
    
    var owner: String {
        get { self.owner_ ?? "(null)"  }
        set { self.owner_ = newValue }
    }
    
    @objc var columnName: String {
        get { self.columnName_ ?? "(null)"  }
        set { self.columnName_ = newValue }
    }
    
    @objc var dataType: String {
        get { self.dataType_ ?? "(null)"  }
        set { self.dataType_ = newValue }
    }
    
    @objc var dataTypeMod: String {
        get { self.dataType_ ?? "(null)"  }
        set { self.dataType_ = newValue }
    }
    
    @objc var dataTypeOwner: String {
        get { self.dataTypeOwner_ ?? "(null)"  }
        set { self.dataTypeOwner_ = newValue }
    }
    
    public class func fetchRequestSorted() -> NSFetchRequest<DBCacheTableColumn> {
        let request = NSFetchRequest<DBCacheTableColumn>(entityName: "DBCacheTableColumn")
        request.sortDescriptors = [NSSortDescriptor(key: "internalColumnID", ascending: true)]
        return request
    }
}

