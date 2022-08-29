//
//  DBCacheIndex+CoreDataProperties.swift
//  DBObjectsBrowser
//
//  Created by Ilia on 6/20/22.
//

import Foundation
import CoreData

//@objc public enum IndexType: Int16 {
//    case normal, bitmap, cluster, iot, function, unknown
//}

extension DBCacheIndex {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<DBCacheIndex> {
        return NSFetchRequest<DBCacheIndex>(entityName: "DBCacheIndex")
    }
    @NSManaged public var avgDataBlocksPerKey: Double
    @NSManaged public var avgLeafBlocksPerKey: Double
    @NSManaged public var clusteringFactor: Int64
    @NSManaged public var degree_: String?
    @NSManaged public var distinctKeys: Int64
    @NSManaged public var isPartitioned: Bool
    @NSManaged public var isValid: Bool
    @NSManaged public var isVisible: Bool
    @NSManaged public var isUnique: Bool
    @NSManaged public var lastAnalyzed: Date?
    @NSManaged public var leafBlocks: Int64
    @NSManaged public var name_: String?
    @NSManaged public var numRows: Int64
    @NSManaged public var owner_: String?
    @NSManaged public var sampleSize: Int64
    @NSManaged public var tableName_: String?
    @NSManaged public var tableOwner_: String?
    @NSManaged public var tablespaceName_: String?
    @NSManaged public var type_: String?
}


extension DBCacheIndex : Identifiable {
    
}

extension DBCacheIndex {
    var name: String {
        get { self.name_ ?? "(null)" }
        set { self.name_ = newValue }
    }
    
    var type: String {
        get { self.type_ ?? "(null)" }
        set { self.type_ = newValue }
    }
    
    var owner: String {
        get { self.owner_ ?? "(null)"  }
        set { self.owner_ = newValue }
    }
    
    var tableName: String {
        get { self.tableName_ ?? "(null)" }
        set { self.tableName_ = newValue }
    }
    
    var tableOwner: String {
        get { self.tableOwner_ ?? "(null)"  }
        set { self.tableOwner_ = newValue }
    }
    
    var degree: String {
        get { self.degree_ ?? "(null)"  }
        set { self.degree_ = newValue }
    }
    
    var tablespaceName: String {
        get { self.tablespaceName_ ?? "(null)"  }
        set { self.tablespaceName_ = newValue }
    }
}
