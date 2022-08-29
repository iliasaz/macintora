//
//  ConnDatabase+CoreDataProperties.swift
//  
//
//  Created by Ilia on 1/5/22.
//
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData


extension ConnDatabase {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ConnDatabase> {
        return NSFetchRequest<ConnDatabase>(entityName: "ConnDatabase")
    }

    @NSManaged public var dbid: Int64
    @NSManaged public var lastUpdate: Date?
    @NSManaged public var tnsAlias_: String?
    @NSManaged public var versionFull: String?
    @NSManaged public var versionMajor: Int16

}

extension ConnDatabase : Identifiable {

}

extension ConnDatabase: Comparable {
    
    public static func < (lhs: ConnDatabase, rhs: ConnDatabase) -> Bool {
        lhs.tnsAlias < rhs.tnsAlias
    }
    
    var tnsAlias: String {
        get { self.tnsAlias_! }
        set { self.tnsAlias_ = newValue }
    }
    
    static func fetchRequest(_ predicate: NSPredicate) -> NSFetchRequest<ConnDatabase> {
        let request = NSFetchRequest<ConnDatabase>(entityName: "ConnDatabase")
        request.sortDescriptors = [NSSortDescriptor(key: "tnsAlias_", ascending: true)]
        request.predicate = predicate
        return request
    }
    
    static func fetchRequest(tns: String) -> NSFetchRequest<ConnDatabase> {
        return fetchRequest(NSPredicate(format: "tnsAlias_ = %@", tns))
    }
}

