//
//  DBCacheProcedureArgument+CoreDataProperties.swift
//  Macintora
//

import Foundation
import CoreData


extension DBCacheProcedureArgument {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<DBCacheProcedureArgument> {
        return NSFetchRequest<DBCacheProcedureArgument>(entityName: "DBCacheProcedureArgument")
    }

    @NSManaged public var argumentName_: String?
    @NSManaged public var charLength: Int32
    @NSManaged public var dataLength: Int32
    @NSManaged public var dataLevel: Int16
    @NSManaged public var dataPrecision: Int16
    @NSManaged public var dataScale: Int16
    @NSManaged public var dataType_: String?
    @NSManaged public var defaultValue_: String?
    @NSManaged public var defaulted: Bool
    @NSManaged public var inOut_: String?
    @NSManaged public var objectName_: String?
    @NSManaged public var overload_: String?
    @NSManaged public var owner_: String?
    @NSManaged public var plsType_: String?
    @NSManaged public var position: Int16
    @NSManaged public var procedureName_: String?
    @NSManaged public var sequence: Int16
    @NSManaged public var subprogramId: Int32
    @NSManaged public var typeName_: String?
    @NSManaged public var typeOwner_: String?
    @NSManaged public var typeSubname_: String?
}


extension DBCacheProcedureArgument: Identifiable {

}

extension DBCacheProcedureArgument {
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

    var argumentName: String {
        get { self.argumentName_ ?? "" }
        set { self.argumentName_ = newValue }
    }

    var dataType: String {
        get { self.dataType_ ?? "" }
        set { self.dataType_ = newValue }
    }

    var inOut: String {
        get { self.inOut_ ?? "IN" }
        set { self.inOut_ = newValue }
    }

    var overload: String {
        get { self.overload_ ?? "" }
        set { self.overload_ = newValue }
    }

    var defaultValue: String {
        get { self.defaultValue_ ?? "" }
        set { self.defaultValue_ = newValue }
    }
}

extension DBCacheProcedureArgument {
    @MainActor static var example: DBCacheProcedureArgument {
        let context = PersistenceController.preview.container.viewContext
        let request = DBCacheProcedureArgument.fetchRequest()
        request.fetchLimit = 1
        let results = try? context.fetch(request)
        return (results?.first!)!
    }
}
