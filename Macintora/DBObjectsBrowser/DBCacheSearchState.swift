//
//  DBCacheSearchState.swift
//
//  Created by Ilia on 1/17/22.
//

import Foundation

struct DBCacheSearchState: Equatable, Codable {
    var searchText = ""
    var prefixString = ""
    var ownerString = ""
    var showTables = true
    var showViews = false
    var showPackages = false
    var showProcedures = false
    var showFunctions = false
}

