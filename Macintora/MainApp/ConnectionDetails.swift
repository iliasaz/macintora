//
//  ConnectionDetails.swift
//  Macintora
//
//  Created by Ilia Sazonov on 8/25/22.
//

import Foundation

nonisolated enum ConnectionRole: String, Codable, Sendable {
    case regular, sysDBA
}

/// Per-document connection state.
///
/// Since the connection-manager overhaul, this struct is *not* the source of
/// truth for connection endpoints. ``ConnectionStore`` is. ``ConnectionDetails``
/// references a saved connection by ``savedConnectionID`` and carries the
/// per-document overrides:
///
/// - ``username`` — override of the saved connection's `defaultUsername`.
/// - ``password`` — session-only, never persisted to disk.
/// - ``connectionRole`` — sysDBA toggle, per document.
///
/// The ``tns`` field is retained as a *display name snapshot* (the saved
/// connection's name at the time the document was saved). It's used by the
/// DBCache and SessionBrowser windows for titles and as the per-connection
/// CoreData store name. It's also the migration anchor: documents written by
/// pre-overhaul versions have only ``tns`` populated; on load, we record it as
/// the legacy alias so the migration step can match it against the store.
nonisolated struct ConnectionDetails: CustomStringConvertible, Hashable, Equatable, Sendable {
    var description: String { "username: \(username), tns: \(tns), connectionRole: \(connectionRole)" }

    var savedConnectionID: UUID?
    var username: String
    /// Session-only credential. Excluded from `Codable`.
    var password: String
    /// Display name / legacy alias. Snapshot of the saved connection's name.
    var tns: String
    var connectionRole: ConnectionRole

    init(
        savedConnectionID: UUID? = nil,
        username: String = "",
        password: String = "",
        tns: String = "",
        connectionRole: ConnectionRole = .regular
    ) {
        self.savedConnectionID = savedConnectionID
        self.username = username
        self.password = password
        self.tns = tns
        self.connectionRole = connectionRole
    }

    static func preview() -> ConnectionDetails {
        ConnectionDetails(username: "username", password: "password", tns: "tns", connectionRole: .regular)
    }
}

extension ConnectionDetails: Codable {
    private enum CodingKeys: String, CodingKey {
        case savedConnectionID, username, tns, connectionRole
    }

  init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.savedConnectionID = try c.decodeIfPresent(UUID.self, forKey: .savedConnectionID)
        self.username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        self.tns = try c.decodeIfPresent(String.self, forKey: .tns) ?? ""
        self.connectionRole = try c.decodeIfPresent(ConnectionRole.self, forKey: .connectionRole) ?? .regular
        // Password is intentionally not decoded — it's session-only.
        self.password = ""
    }

  func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(savedConnectionID, forKey: .savedConnectionID)
        try c.encode(username, forKey: .username)
        try c.encode(tns, forKey: .tns)
        try c.encode(connectionRole, forKey: .connectionRole)
        // Password intentionally omitted.
    }
}

nonisolated struct OracleSession: CustomStringConvertible, Codable, Hashable, Equatable, Sendable {
    var description: String { "sid: \(sid), serial#: \(serial), instance: \(instance), timezone: \(dbTimeZone.debugDescription)" }

    let sid: Int
    let serial: Int
    let instance: Int
    let dbTimeZone: TimeZone?

    static func preview() -> OracleSession {
        OracleSession(sid: -100, serial: -2000, instance: -1, dbTimeZone: .current)
    }
}

nonisolated struct MainConnection: CustomStringConvertible, Hashable, Codable, Equatable, Sendable {
    var description: String {
        "mainConnDetails: \(mainConnDetails), mainSession: \(mainSession.map(String.init(describing:)) ?? "nil")"
    }

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
