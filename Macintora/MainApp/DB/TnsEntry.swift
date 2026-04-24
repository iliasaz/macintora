import Foundation

/// A resolved tnsnames.ora entry.
nonisolated struct TnsEntry: Hashable, Sendable, Codable {
    let alias: String
    let host: String
    let port: Int
    let serviceName: String?
    let sid: String?

    init(alias: String, host: String, port: Int, serviceName: String? = nil, sid: String? = nil) {
        self.alias = alias
        self.host = host
        self.port = port
        self.serviceName = serviceName
        self.sid = sid
    }
}
