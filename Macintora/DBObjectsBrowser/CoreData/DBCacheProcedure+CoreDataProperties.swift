//
//  DBCacheProcedure+CoreDataProperties.swift
//  Macintora
//

import Foundation
import CoreData


extension DBCacheProcedure {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<DBCacheProcedure> {
        return NSFetchRequest<DBCacheProcedure>(entityName: "DBCacheProcedure")
    }

    @NSManaged public var authID_: String?
    @NSManaged public var implTypeName_: String?
    @NSManaged public var implTypeOwner_: String?
    @NSManaged public var isAggregate: Bool
    @NSManaged public var isDeterministic: Bool
    @NSManaged public var isParallel: Bool
    @NSManaged public var isPipelined: Bool
    @NSManaged public var isResultCache: Bool
    @NSManaged public var objectName_: String?
    @NSManaged public var objectType_: String?
    @NSManaged public var overload_: String?
    @NSManaged public var owner_: String?
    @NSManaged public var procedureName_: String?
    @NSManaged public var subprogramId: Int32
}


extension DBCacheProcedure: Identifiable {

}

extension DBCacheProcedure {
    var owner: String {
        get { self.owner_ ?? "(null)" }
        set { self.owner_ = newValue }
    }

    var objectName: String {
        get { self.objectName_ ?? "(null)" }
        set { self.objectName_ = newValue }
    }

    var procedureName: String {
        get { self.procedureName_ ?? "" }
        set { self.procedureName_ = newValue }
    }

    var objectType: String {
        get { self.objectType_ ?? "(null)" }
        set { self.objectType_ = newValue }
    }

    var overload: String {
        get { self.overload_ ?? "" }
        set { self.overload_ = newValue }
    }

    var authID: String {
        get { self.authID_ ?? "" }
        set { self.authID_ = newValue }
    }
}

extension DBCacheProcedure {
    @MainActor static var example: DBCacheProcedure {
        let context = PersistenceController.preview.container.viewContext
        let request = DBCacheProcedure.fetchRequest()
        request.fetchLimit = 1
        let results = try? context.fetch(request)
        return (results?.first!)!
    }
}
