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

struct ConnectionDetails: CustomStringConvertible, Codable, Hashable, Equatable {
    var description: String { "username: \(username), tns: \(tns), connectionRole: \(connectionRole)" }
    
    var username: String
    var password: String
    var tns: String
    var connectionRole: ConnectionRole
//    private var shortStrings: [String]? = [String]()
    
    init(username: String = "", password: String = "", tns: String = "preview", connectionRole: ConnectionRole = .regular) {
        self.username = username
        self.password = password
        self.tns = tns
        self.connectionRole = connectionRole
    }
    
    static func preview() -> ConnectionDetails {
        ConnectionDetails(username: "username", password: "password", tns: "tns", connectionRole: .regular)
    }
}

struct OracleSession: CustomStringConvertible, Codable, Hashable, Equatable {
    var description: String { "sid: \(sid), serial#: \(serial), instance: \(instance), timezone: \(dbTimeZone.debugDescription)" }
    
    let sid: Int
    let serial: Int
    let instance: Int
    let dbTimeZone: TimeZone?
    
    static func preview() -> OracleSession {
        OracleSession(sid: -100, serial: -2000, instance: -1, dbTimeZone: .current)
    }
}

struct MainConnection: CustomStringConvertible, Hashable, Codable, Equatable {
    var description: String { "mainConnDetails: \(mainConnDetails), mainSession: \(mainSession)" }
    
    static func == (lhs: MainConnection, rhs: MainConnection) -> Bool {
        lhs.mainConnDetails == rhs.mainConnDetails && (lhs.mainSession ?? .preview() == rhs.mainSession ?? .preview())
    }
    
    var mainConnDetails: ConnectionDetails
    var mainSession: OracleSession?
    
    static func preview() -> MainConnection {
        MainConnection(mainConnDetails: ConnectionDetails.preview(), mainSession: OracleSession.preview())
    }
    
    init(mainConnDetails: ConnectionDetails, mainSession: OracleSession? = nil) {
        self.mainConnDetails = mainConnDetails
        self.mainSession = mainSession
    }
}


