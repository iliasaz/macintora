//
//  DBCacheSearchCriteria.swift
//
//  Created by Ilia on 1/17/22.
//

import Foundation
import CoreData

class DBCacheSearchCriteria: ObservableObject {
    @Published var searchText = ""
    @Published var prefixString = ""
    @Published var ownerString = ""
    @Published var showTables = true
    @Published var showViews = false
    @Published var showPackages = false
    @Published var showProcedures = false
    @Published var showFunctions = false
    
    
    init() {}
    
    var predicate: NSPredicate {
        var predicates = [NSPredicate]()
        var ownerInclusionList = [String]()
        var namePrefixInclusionList = [String]()
        var typeInclusionList = [String]()
        var ownerPrefixExclusionList = ["SYS", "CDR_W"]

        namePrefixInclusionList = prefixString.components(separatedBy: ",").compactMap { let trimmed = $0.uppercased().trimmingCharacters(in: .whitespaces); return trimmed.isEmpty ? nil : trimmed }
        ownerInclusionList = ownerString.uppercased().components(separatedBy: ",").compactMap { let trimmed = $0.trimmingCharacters(in: .whitespaces); return trimmed.isEmpty ? nil : trimmed }
        if showTables { typeInclusionList.append("TABLE") }
        if showProcedures { typeInclusionList.append("PROCEDURE") }
        if showFunctions { typeInclusionList.append("FUNCTION") }
        if showViews { typeInclusionList.append("VIEW") }
        if showPackages { typeInclusionList.append("PACKAGE") }
        
        if !ownerInclusionList.isEmpty {
            predicates.append(NSPredicate.init(format: "owner_ IN %@", ownerInclusionList))
        }
        if !typeInclusionList.isEmpty {
            predicates.append(NSPredicate.init(format: "type_ IN %@", typeInclusionList))
        }
        
        if !searchText.isEmpty {
            predicates.append(NSPredicate.init(format: "name_ CONTAINS[c] %@", searchText))
        }
        if !namePrefixInclusionList.isEmpty {
            predicates.append(NSCompoundPredicate.init(type: .or, subpredicates: namePrefixInclusionList.map { NSPredicate.init(format: "name_ BEGINSWITH[c] %@", $0) } ))
        }
        
        //        predicates.append(NSCompoundPredicate.init(format: "name_ = %@", "CDR_JOBS"))
        log.debug("criteria: \(predicates)")
        return NSCompoundPredicate.init(type: .and, subpredicates: predicates)
    }
    
//    var sort: [NSSortDescriptor] {
//        var sorts = [NSSortDescriptor]()
//        sorts.append(NSSortDescriptor(keyPath: \DBCacheObject.name_, ascending: true))
//        sorts.append(NSSortDescriptor(keyPath: \DBCacheObject.owner_, ascending: true))
//        sorts.append(NSSortDescriptor(keyPath: \DBCacheObject.type_, ascending: true))
//        return sorts
//    }
    
//    var fetchParams: (NSPredicate, [NSSortDescriptor]) {
//        (predicate, sort)
//    }
    
//    var fetchRequest: NSFetchRequest<DBCacheObject> {
//        let request = DBCacheObject.fetchRequest()
//        request.predicate = predicate
//        request.sortDescriptors = sort
//        request.fetchLimit = 50
//        return request
//    }
    
}
