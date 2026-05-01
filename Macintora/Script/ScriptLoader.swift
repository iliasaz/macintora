//
//  ScriptLoader.swift
//  Macintora
//
//  Resolves `@file.sql` / `@@file.sql` includes in a unit list. Pre-runner
//  pass: walks the lexed units, expands every encountered include in-place,
//  and recurses with cycle detection.
//
//  Path semantics:
//    - `@file`  → resolve against `documentBaseURL` (the running document's
//                 directory).
//    - `@@file` → resolve against the URL of the *currently-being-included*
//                 file. Falls back to `documentBaseURL` for the top-level
//                 script.
//    - If the path lacks an extension, `.sql` is appended.
//

import Foundation

enum ScriptLoaderError: Error, Equatable {
    case fileNotFound(path: String, resolvedURL: URL)
    case cycleDetected(path: URL)
    case readFailed(path: URL, underlying: String)
    case maxDepthExceeded(limit: Int)
}

/// Abstraction over `Foundation` file I/O so tests can inject a fake.
protocol ScriptFileResolver: Sendable {
    /// Read the contents of `url`, or throw if the file isn't readable.
    func read(_ url: URL) throws -> String
    /// Whether the file at `url` exists and is readable.
    func exists(_ url: URL) -> Bool
}

struct DefaultScriptFileResolver: ScriptFileResolver {
    func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

enum ScriptLoader {
    /// Recursive flattening: walks `units`, expanding every `.include`
    /// directive into the target file's units. Cycles return
    /// `.cycleDetected`.
    ///
    /// `documentBaseURL` is the directory of the running document (used to
    /// resolve `@file`); `nil` if the document isn't backed by a file (yet),
    /// in which case any `@file` errors out with `.fileNotFound`.
    static func flatten(
        _ units: [CommandUnit],
        documentBaseURL: URL?,
        resolver: any ScriptFileResolver = DefaultScriptFileResolver(),
        maxDepth: Int = 16
    ) throws -> [CommandUnit] {
        var visited: Set<URL> = []
        return try flatten(
            units: units,
            currentFileURL: nil,
            documentBaseURL: documentBaseURL,
            resolver: resolver,
            visited: &visited,
            depth: 0,
            maxDepth: maxDepth
        )
    }

    private static func flatten(
        units: [CommandUnit],
        currentFileURL: URL?,
        documentBaseURL: URL?,
        resolver: any ScriptFileResolver,
        visited: inout Set<URL>,
        depth: Int,
        maxDepth: Int
    ) throws -> [CommandUnit] {
        if depth > maxDepth {
            throw ScriptLoaderError.maxDepthExceeded(limit: maxDepth)
        }

        var output: [CommandUnit] = []
        for unit in units {
            switch unit.kind {
            case .sqlplus(.include(let rawPath, let doubleAt)):
                let resolvedURL = try resolveURL(
                    rawPath: rawPath,
                    doubleAt: doubleAt,
                    currentFileURL: currentFileURL,
                    documentBaseURL: documentBaseURL,
                    resolver: resolver
                )
                if visited.contains(resolvedURL) {
                    throw ScriptLoaderError.cycleDetected(path: resolvedURL)
                }
                let body: String
                do {
                    body = try resolver.read(resolvedURL)
                } catch {
                    throw ScriptLoaderError.readFailed(path: resolvedURL, underlying: error.localizedDescription)
                }
                visited.insert(resolvedURL)
                let nestedUnits = ScriptLexer.split(body).units
                let expanded = try flatten(
                    units: nestedUnits,
                    currentFileURL: resolvedURL,
                    documentBaseURL: documentBaseURL,
                    resolver: resolver,
                    visited: &visited,
                    depth: depth + 1,
                    maxDepth: maxDepth
                )
                output.append(contentsOf: expanded)
                visited.remove(resolvedURL)

            default:
                output.append(unit)
            }
        }
        return output
    }

    /// Public for test ergonomics; computes the URL that an include would
    /// resolve to without performing any I/O beyond `resolver.exists(_:)`.
    static func resolveURL(
        rawPath: String,
        doubleAt: Bool,
        currentFileURL: URL?,
        documentBaseURL: URL?,
        resolver: any ScriptFileResolver
    ) throws -> URL {
        // Absolute paths bypass any base anchor.
        if rawPath.hasPrefix("/") {
            let url = URL(fileURLWithPath: rawPath)
            let withExt = ensureSqlExtension(url, resolver: resolver)
            guard resolver.exists(withExt) else {
                throw ScriptLoaderError.fileNotFound(path: rawPath, resolvedURL: withExt)
            }
            return withExt
        }

        let baseURL: URL
        if doubleAt, let current = currentFileURL {
            baseURL = current.deletingLastPathComponent()
        } else if let base = documentBaseURL {
            baseURL = base
        } else {
            let url = URL(fileURLWithPath: rawPath)
            throw ScriptLoaderError.fileNotFound(path: rawPath, resolvedURL: url)
        }

        let candidate = baseURL.appendingPathComponent(rawPath).standardizedFileURL
        let withExt = ensureSqlExtension(candidate, resolver: resolver)
        guard resolver.exists(withExt) else {
            throw ScriptLoaderError.fileNotFound(path: rawPath, resolvedURL: withExt)
        }
        return withExt
    }

    private static func ensureSqlExtension(_ url: URL, resolver: any ScriptFileResolver) -> URL {
        if resolver.exists(url) { return url }
        guard url.pathExtension.isEmpty else { return url }
        return url.appendingPathExtension("sql")
    }
}
