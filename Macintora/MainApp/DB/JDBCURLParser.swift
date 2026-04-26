import Foundation

/// Parses Oracle JDBC connect URLs into the structured fields the connection
/// editor expects. Handles the common forms that appear in cloud/console UIs:
///
/// - `jdbc:oracle:thin:@host:port:SID` (legacy)
/// - `jdbc:oracle:thin:@host:port/service`
/// - `jdbc:oracle:thin:@//host:port/service`
/// - `jdbc:oracle:thin:@(DESCRIPTION=(ADDRESS=...)(CONNECT_DATA=...))`
/// - `jdbc:oracle:thin:@tcps://host:port/service` (TLS, no wallet path)
///
/// The `jdbc:oracle:thin:` prefix is optional; users often paste just the `@…`
/// payload from documentation snippets.
nonisolated enum JDBCURLParser {
    enum ParseError: Error, LocalizedError {
        case empty
        case unrecognizedScheme(String)
        case malformed(String)
        case missingService(String)

        var errorDescription: String? {
            switch self {
            case .empty: "Empty URL"
            case .unrecognizedScheme(let s): "Unrecognized scheme: \(s)"
            case .malformed(let s): "Could not parse '\(s)' as a JDBC URL"
            case .missingService(let s): "URL '\(s)' has no service name or SID"
            }
        }
    }

    struct Result: Equatable, Sendable {
        var host: String
        var port: Int
        var service: ServiceIdentifier
        var tls: TLSSettings
    }

    static func parse(_ raw: String) throws -> Result {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParseError.empty }

        let payload: String
        if let atIndex = trimmed.firstIndex(of: "@") {
            let prefix = trimmed[..<atIndex].lowercased()
            if !prefix.isEmpty, !prefix.hasSuffix("jdbc:oracle:thin:") && prefix != "jdbc:oracle:thin" {
                throw ParseError.unrecognizedScheme(String(trimmed[..<atIndex]))
            }
            payload = String(trimmed[trimmed.index(after: atIndex)...])
        } else {
            payload = trimmed
        }

        let body = payload.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { throw ParseError.malformed(raw) }

        if body.hasPrefix("(") {
            return try parseDescriptor(body, raw: raw)
        }

        let (transport, remainder) = stripTransportScheme(body)
        return try parseHostPortService(remainder, transport: transport, raw: raw)
    }

    private static func stripTransportScheme(_ body: String) -> (TLSSettings, String) {
        let lower = body.lowercased()
        if lower.hasPrefix("tcps://") {
            return (.system, String(body.dropFirst("tcps://".count)))
        }
        if lower.hasPrefix("tcp://") {
            return (.disabled, String(body.dropFirst("tcp://".count)))
        }
        if body.hasPrefix("//") {
            return (.disabled, String(body.dropFirst(2)))
        }
        return (.disabled, body)
    }

    private static func parseHostPortService(
        _ body: String,
        transport: TLSSettings,
        raw: String
    ) throws -> Result {
        let host: String
        let port: Int
        let service: ServiceIdentifier

        if let slash = body.firstIndex(of: "/") {
            (host, port) = try splitHostPort(String(body[..<slash]), raw: raw)
            let svcRaw = body[body.index(after: slash)...].trimmingCharacters(in: .whitespaces)
            guard !svcRaw.isEmpty else { throw ParseError.missingService(raw) }
            service = .serviceName(String(svcRaw))
            return Result(host: host, port: port, service: service, tls: transport)
        }

        let parts = body.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        switch parts.count {
        case 3:
            host = parts[0]
            guard let p = Int(parts[1]) else { throw ParseError.malformed(raw) }
            port = p
            let sid = parts[2].trimmingCharacters(in: .whitespaces)
            guard !sid.isEmpty else { throw ParseError.missingService(raw) }
            service = .sid(sid)
            return Result(host: host, port: port, service: service, tls: transport)
        case 2, 1:
            throw ParseError.missingService(raw)
        default:
            throw ParseError.malformed(raw)
        }
    }

    private static func splitHostPort(_ s: String, raw: String) throws -> (String, Int) {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ParseError.malformed(raw) }
        if let colon = trimmed.firstIndex(of: ":") {
            let h = String(trimmed[..<colon])
            guard let p = Int(trimmed[trimmed.index(after: colon)...]) else {
                throw ParseError.malformed(raw)
            }
            guard !h.isEmpty else { throw ParseError.malformed(raw) }
            return (h, p)
        }
        return (trimmed, 1521)
    }

    private static func parseDescriptor(_ body: String, raw: String) throws -> Result {
        guard let entry = TnsParser.parseDescriptor(body) else {
            throw ParseError.malformed(raw)
        }
        let svc: ServiceIdentifier =
            if let s = entry.serviceName { .serviceName(s) }
            else if let s = entry.sid { .sid(s) }
            else { throw ParseError.missingService(raw) }
        let tls: TLSSettings = body.range(of: "PROTOCOL\\s*=\\s*tcps", options: [.regularExpression, .caseInsensitive]) != nil ? .system : .disabled
        return Result(host: entry.host, port: entry.port, service: svc, tls: tls)
    }
}
