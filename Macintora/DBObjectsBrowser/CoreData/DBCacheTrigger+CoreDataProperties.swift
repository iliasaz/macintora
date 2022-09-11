//
//  DBCacheTrigger+CoreDataProperties.swift
//  Macintora
//
//  Created by Ilia Sazonov on 9/6/22.
//

import Foundation
import CoreData


extension DBCacheTrigger {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<DBCacheTrigger> {
        return NSFetchRequest<DBCacheTrigger>(entityName: "DBCacheTrigger")
    }
    @NSManaged public var actionType_: String?
    @NSManaged public var body: String?
    @NSManaged public var columnName: String?
    @NSManaged public var descr: String?
    @NSManaged public var event_: String?
    @NSManaged public var isAfterRow: Bool
    @NSManaged public var isAfterStatement: Bool
    @NSManaged public var isBeforeRow: Bool
    @NSManaged public var isBeforeStatement: Bool
    @NSManaged public var isCrossEdition: Bool
    @NSManaged public var isEnabled: Bool
    @NSManaged public var isFireOnce: Bool
    @NSManaged public var isInsteadOfRow: Bool
    @NSManaged public var name_: String?
    @NSManaged public var objectName: String?
    @NSManaged public var objectOwner: String?
    @NSManaged public var objectType_: String?
    @NSManaged public var owner_: String?
    @NSManaged public var referencingNames: String?
    @NSManaged public var type_: String?
    @NSManaged public var whenClause: String?
}


extension DBCacheTrigger : Identifiable {

}

extension DBCacheTrigger {
    var name: String {
        get { self.name_ ?? "(null)" }
        set { self.name_ = newValue }
    }
    
    var owner: String {
        get { self.owner_ ?? "(null)"  }
        set { self.owner_ = newValue }
    }
    
    var type: String {
        get { self.type_ ?? "(null)"  }
        set { self.type_ = newValue }
    }
    
    var actionType: String {
        get { self.actionType_ ?? "(null)"  }
        set { self.actionType_ = newValue }
    }
    
    var event: String {
        get { self.event_ ?? "(null)"  }
        set { self.event_ = newValue }
    }
    
    var objectType: String {
        get { self.objectType_ ?? "(null)"  }
        set { self.objectType_ = newValue }
    }

}

extension DBCacheTrigger {
    static var example: DBCacheTrigger {
        let context = PersistenceController.preview.container.viewContext
        let request = DBCacheTrigger.fetchRequest()
        request.fetchLimit = 1
        let results = try? context.fetch(request)
        return (results?.first!)!
    }
}
