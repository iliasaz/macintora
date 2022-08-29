//
//  MacOraModel.swift
//  MacOra
//
//  Created by Ilia Sazonov on 10/4/21.
//

import Foundation
import SwiftOracle

struct MainModel: Identifiable, Codable, CustomStringConvertible {
    var description: String {
        "tns: \(connectionDetails.tns), username: \(connectionDetails.username), connection role: \(connectionDetails.connectionRole)"
    }
    
    var id = UUID()
    var text: String
    var connectionDetails: ConnectionDetails
    
    var preferences = [String:String]()
    var quickFilterPrefs: DBCacheSearchState
    var autoConnect:Bool? = false

    init(text: String, quickFilterPrefs: DBCacheSearchState = DBCacheSearchState()) {
        self.text = text
        self.quickFilterPrefs = quickFilterPrefs
        self.connectionDetails = ConnectionDetails()
    }
    
}
