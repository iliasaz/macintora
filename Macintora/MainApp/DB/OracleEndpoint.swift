import Foundation
import OracleNIO

/// Resolves ``ConnectionDetails`` into an ``OracleConnection.Configuration`` that oracle-nio
/// can consume.
///
/// Lookup order for the `tns` field on ``ConnectionDetails``:
/// 1. If it matches a ``TnsEntry`` alias in the provided list, use that entry's host/port/service.
/// 2. Otherwise, attempt to parse it as a manual endpoint: `host[:port][/service]` or
///    `host[:port]:sid`. This is the escape hatch for users without a tnsnames.ora.
nonisolated enum OracleEndpoint {
    enum ResolveError: Error, LocalizedError {
        case unknownAlias(String)
        case malformedManualEndpoint(String)

        var errorDescription: String? {
            switch self {
            case .unknownAlias(let alias):
                "TNS alias '\(alias)' not found and could not be parsed as host:port/service."
            case .malformedManualEndpoint(let raw):
                "Could not interpret '\(raw)' as host:port/service or host:port:sid."
            }
        }
    }

    static func configuration(
        for details: ConnectionDetails,
        aliases: [TnsEntry]
    ) throws -> OracleConnection.Configuration {
        let resolved = try resolve(tnsField: details.tns, aliases: aliases)
        return makeConfiguration(
            entry: resolved,
            username: details.username,
            password: details.password,
            sysDBA: details.connectionRole == .sysDBA
        )
    }

    static func resolve(tnsField: String, aliases: [TnsEntry]) throws -> TnsEntry {
        let key = tnsField.lowercased()
        if let match = aliases.first(where: { $0.alias.lowercased() == key }) {
            return match
        }
        return try parseManualEndpoint(tnsField)
    }

    /// `host[:port][/serviceName]`  OR  `host[:port]:sid` when prefixed with colon-sid form is not supported —
    /// the `/` separator unambiguously indicates a service name; use `@host:port/svc` style from Oracle URLs.
    static func parseManualEndpoint(_ raw: String) throws -> TnsEntry {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ResolveError.malformedManualEndpoint(raw) }

        let hostPart: String
        let servicePart: String?
        if let slash = trimmed.firstIndex(of: "/") {
            hostPart = String(trimmed[..<slash])
            servicePart = String(trimmed[trimmed.index(after: slash)...])
        } else {
            hostPart = trimmed
            servicePart = nil
        }

        let host: String
        let port: Int
        if let colon = hostPart.firstIndex(of: ":") {
            host = String(hostPart[..<colon])
            guard let p = Int(hostPart[hostPart.index(after: colon)...]) else {
                throw ResolveError.malformedManualEndpoint(raw)
            }
            port = p
        } else {
            host = hostPart
            port = 1521
        }

        guard !host.isEmpty else { throw ResolveError.malformedManualEndpoint(raw) }
        guard let servicePart, !servicePart.isEmpty else {
            throw ResolveError.malformedManualEndpoint(raw)
        }

        return TnsEntry(alias: raw, host: host, port: port, serviceName: servicePart, sid: nil)
    }

    static func makeConfiguration(
        entry: TnsEntry,
        username: String,
        password: String,
        sysDBA: Bool
    ) -> OracleConnection.Configuration {
        let service: OracleServiceMethod
        if let svc = entry.serviceName {
            service = .serviceName(svc)
        } else if let sid = entry.sid {
            service = .sid(sid)
        } else {
            service = .serviceName(entry.alias)
        }
        var config = OracleConnection.Configuration(
            host: entry.host,
            port: entry.port,
            service: service,
            username: username,
            password: password
        )
        if sysDBA {
            config.mode = .sysDBA
        }
        return config
    }
}
