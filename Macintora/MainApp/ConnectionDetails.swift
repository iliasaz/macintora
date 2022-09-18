//
//  ConnectionDetails.swift
//  Macintora
//
//  Created by Ilia Sazonov on 8/25/22.
//

import Foundation

enum ConnectionRole: String, Codable {
    case regular, sysDBA
}

struct ConnectionDetails: Codable, Hashable {
    var username: String
    var password: String
    var tns: String
    var connectionRole: ConnectionRole
    
    init(username: String = "", password: String = "", tns: String = "preview", connectionRole: ConnectionRole = .regular) {
        self.username = username
        self.password = password
        self.tns = tns
        self.connectionRole = connectionRole
    }
    
    static func preview() -> ConnectionDetails {
        ConnectionDetails(username: "username")
    }
    
//    static func < (lhs: ConnectionDetails, rhs: ConnectionDetails) -> Bool {
//        let result = lhs.tns < rhs.tns //&& ( lhs.username ?? "" < rhs.username ?? "" )
//        return result
//    }
}

//struct CacheConnectionDetails {
//    var username: String
//    var password: String
//    var tns: String
//    var connectionRole: ConnectionRole
//
//    init(from connDetails: ConnectionDetails) {
//        self.username = connDetails.username
//        self.password = connDetails.password
//        self.tns = connDetails.tns
//        self.connectionRole = connDetails.connectionRole
//    }
//}

