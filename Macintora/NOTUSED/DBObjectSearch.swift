//
//  DBObjectSearch.swift
//  MacOra
//
//  Created by Ilia on 12/14/21.
//

import Foundation
import CoreData

struct DBObjectSearch: CustomStringConvertible {
    var description: String {
        return "ownerInclusionList: \(ownerInclusionList), nameFilter: \(nameFilter), namePrefixInclusionList: \(namePrefixInclusionList), typeInclusionList: \(typeInclusionList)"
    }
    
    var ownerInclusionList = [String]()
    var nameFilter: String
    var namePrefixInclusionList = [String]()
    var typeInclusionList = [String]()
//    var ownerPrefixExclusionList = ["SYS", "CDR_W"]
    
    init(for state: DBObjectBrowserSearchState) {
        nameFilter = state.searchText
        namePrefixInclusionList = state.prefixString.components(separatedBy: ",").compactMap { let trimmed = $0.uppercased().trimmingCharacters(in: .whitespaces); return trimmed.isEmpty ? nil : trimmed }
        ownerInclusionList = state.ownerString.components(separatedBy: ",").compactMap { let trimmed = $0.uppercased().trimmingCharacters(in: .whitespaces); return trimmed.isEmpty ? nil : trimmed }
        if state.showTables { typeInclusionList.append("TABLE") }
        if state.showProcedures { typeInclusionList.append("PROCEDURE") }
        if state.showFunctions { typeInclusionList.append("FUNCTION") }
        if state.showViews { typeInclusionList.append("VIEW") }
        if state.showPackages { typeInclusionList.append("PACKAGE") }
    }
    
    var predicate: NSPredicate {
        var predicates = [NSPredicate]()
        if !ownerInclusionList.isEmpty {
            predicates.append(NSPredicate.init(format: "owner_ IN %@", ownerInclusionList))
        }
        if !typeInclusionList.isEmpty {
            predicates.append(NSPredicate.init(format: "type_ IN %@", typeInclusionList))
        }
        
        if !nameFilter.isEmpty {
            predicates.append(NSPredicate.init(format: "name_ CONTAINS[c] %@", nameFilter))
        }
        if !namePrefixInclusionList.isEmpty {
            predicates.append(NSCompoundPredicate.init(type: .or, subpredicates: namePrefixInclusionList.map { NSPredicate.init(format: "name_ BEGINSWITH[c] %@", $0) } ))
        }
        
//        predicates.append(NSCompoundPredicate.init(format: "name_ = %@", "CDR_JOBS"))
        return NSCompoundPredicate.init(type: .and, subpredicates: predicates)
    }
    
    var sort: [NSSortDescriptor] {
        var sorts = [NSSortDescriptor]()
        sorts.append(NSSortDescriptor(keyPath: \DBCacheObject.name_, ascending: true))
        sorts.append(NSSortDescriptor(keyPath: \DBCacheObject.owner_, ascending: true))
        sorts.append(NSSortDescriptor(keyPath: \DBCacheObject.type_, ascending: true))
        return sorts
    }
    
    var fetchParams: (NSPredicate, [NSSortDescriptor]) {
        (predicate, sort)
    }
    
    var fetchRequest: NSFetchRequest<DBCacheObject> {
        let request = DBCacheObject.fetchRequest()
        request.predicate = predicate
        request.sortDescriptors = sort
        request.fetchLimit = 50
        return request
    }
    
}
