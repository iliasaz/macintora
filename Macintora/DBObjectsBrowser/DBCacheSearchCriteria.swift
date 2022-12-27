//
//  DBCacheSearchCriteria.swift
//
//  Created by Ilia on 1/17/22.
//

import Foundation
import CoreData
import os
import SwiftUI

struct DBCacheSearchCriteria: Equatable {
    static func == (lhs: DBCacheSearchCriteria, rhs: DBCacheSearchCriteria) -> Bool {
        lhs.predicate == rhs.predicate
    }
    
    var searchText = ""
    @AppStorage("prefixList") var prefixList = ["preview": ""] // tns = key: value
    @AppStorage("ownerList") var ownerList = ["preview": ""] // tns = key: value
    @AppStorage("showTables") var showTables = true
    @AppStorage("showViews") var showViews = true
    @AppStorage("showIndexes") var showIndexes = true
    @AppStorage("showPackages") var showPackages = true
    @AppStorage("showTypes") var showTypes = true
    @AppStorage("showTriggers") var showTriggers = true
    @AppStorage("showProcedures") var showProcedures = true
    @AppStorage("showFunctions") var showFunctions = true
//    var changed = false
    
    private let tns: String
    
    var ownerString: String { get { ownerList[tns] ?? "" } set { ownerList[tns] = newValue} }
    var prefixString: String { get { prefixList[tns] ?? "" } set { prefixList[tns] = newValue} }
    
    var ownerInclusionList: [String] {
        ownerString.uppercased().components(separatedBy: ",").compactMap { let trimmed = $0.trimmingCharacters(in: .whitespaces); return trimmed.isEmpty ? nil : trimmed }
    }
    
    var namePrefixInclusionList: [String] {
        prefixString.components(separatedBy: ",").compactMap { let trimmed = $0.uppercased().trimmingCharacters(in: .whitespaces); return trimmed.isEmpty ? nil : trimmed }
    }
    
    init(for tns: String) {
        self.tns = tns
    }
    
    var predicate: NSPredicate {
        var predicates = [NSPredicate]()
        
        var typeInclusionList = [String]()
//        var ownerPrefixExclusionList = ["SYS", "CDR_W"]

        
        
        if showTables { typeInclusionList.append("TABLE") }
        if showTypes { typeInclusionList.append("TYPE") }
        if showProcedures { typeInclusionList.append("PROCEDURE") }
        if showFunctions { typeInclusionList.append("FUNCTION") }
        if showViews { typeInclusionList.append("VIEW") }
        if showIndexes { typeInclusionList.append("INDEX") }
        if showPackages { typeInclusionList.append("PACKAGE") }
        if showTriggers { typeInclusionList.append("TRIGGER") }
        
        if !ownerInclusionList.isEmpty {
            predicates.append(NSPredicate.init(format: "owner_ IN %@", ownerInclusionList))
        }
        if !typeInclusionList.isEmpty {
            predicates.append(NSPredicate.init(format: "type_ IN %@", typeInclusionList))
        }
//
        if !searchText.isEmpty {
            predicates.append(NSPredicate.init(format: "name_ CONTAINS[c] %@", searchText))
        }
        if !namePrefixInclusionList.isEmpty {
            predicates.append(NSCompoundPredicate.init(type: .or, subpredicates: namePrefixInclusionList.map { NSPredicate.init(format: "name_ BEGINSWITH[c] %@", $0) } ))
        }
        
        //        predicates.append(NSCompoundPredicate.init(format: "name_ = %@", "CDR_JOBS"))
        log.cache.debug("criteria: \(predicates, privacy: .public)")
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
