//
//  RunnableSQL.swift
//  Macintora
//
//  Created by Ilia Sazonov on 7/1/22.
//

import Foundation
import CryptoKit
import os

extension Logger {
    var sqlparse: Logger { Logger(subsystem: Logger.subsystem, category: "sqlparse") }
}

struct StoredProc: Equatable {
    let owner: String?
    let name: String
    let type: String
}

struct RunnableSQL: Identifiable {
    let sql: String
    let id: String
    let bindNames: Set<String>
    let isStoredProc: Bool
    let storedProc: StoredProc?
    
    init(sql: String, bindNames: [String] = []) {
        self.sql = sql
        self.id = md5Hash(sql)
        self.bindNames = RunnableSQL.scanBindVars(sql)
        (self.isStoredProc, self.storedProc) = RunnableSQL.detectStoredProc(sql)
    }
    
    static func scanBindVars(_ sql: String?) -> Set<String> {
        log.sqlparse.debug("in scanBindVarrs")
        var ret = Set<String>()
        var quotedRanges = [Range<String.Index>]()
        guard let sql = sql else { return ret }
        let pattern = #"(:\w+)"#
        let exclPattern = #"(('.*?')|(/\*.*?\*/)|(--.*$))+"#

        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let qRegex = try? NSRegularExpression(pattern: exclPattern, options: [.anchorsMatchLines, .dotMatchesLineSeparators])
        let nsRange = NSRange(sql.startIndex..<sql.endIndex, in: sql)
        log.sqlparse.debug("sql: \(sql, privacy: .public)")

        // `matches(in:range:)` returns an array of results; preferred over the
        // older `enumerateMatches(in:range:using:)` because the latter takes an
        // `UnsafeMutablePointer<ObjCBool>` stop flag in its closure (Swift 6.2
        // flags as "unsafe construct"). We don't need early-termination here.
        for match in qRegex?.matches(in: sql, range: nsRange) ?? [] {
            guard let range = Range(match.range, in: sql) else { continue }
            quotedRanges.append(range)
            log.sqlparse.debug("quoted range: \(match.range, privacy: .public), val: \(sql[range], privacy: .public)")
        }

        for match in regex?.matches(in: sql, range: nsRange) ?? [] {
            guard let range = Range(match.range, in: sql) else { continue }
            let val = sql[range]
            log.sqlparse.debug("found potential bind in range \(match.range)")
            if quotedRanges.firstIndex(where: { $0.overlaps(range) }) != nil {
                log.sqlparse.debug("ignoring quoted colon")
                continue
            }
            ret.insert(String(val))
            log.sqlparse.debug("scanBindVars: range: \(match.range, privacy: .public), val: \(val, privacy: .public)")
        }
        log.sqlparse.debug("exiting RunnableSQL.scanBindVar, bind variables identified: \(ret)")
        return ret
    }
    
    static func detectStoredProc(_ sql: String) -> (Bool, StoredProc?) {
        // https://regex101.com/r/m5OckH/1
        log.sqlparse.debug("in detectStoredProc")
        var ret = (false, nil as StoredProc?)
        let createPackagePattern = #"create.*(package\s+body|package)\s+((\"?\w+\"?\.\"?\w+\"?)|(\"?\w+\"?))\s+(\w+\s+)*(as|is)"#
        let createProcedurePattern = #"create.*(procedure)\s+((\"?\w+\"?\.\"?\w+\"?)|(\"?\w+\"?)).*(\(.*\))*.*(as|is)"#
        let createFunctionPattern = #"create.*(function)\s+((\"?\w+\"?\.\"?\w+\"?)|(\"?\w+\"?)).*(\(.*\))*.*(as|is)"#
        let pattern = "(\(createPackagePattern))|(\(createProcedurePattern))|(\(createFunctionPattern))"
//        let pattern = createFunctionPattern
        let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        // don't look for more than 1000 chars
        let nsRange = NSRange(sql.startIndex..<sql.index(sql.startIndex, offsetBy: min(1000, sql.count)), in: sql)
        log.sqlparse.debug("nsRange: \(nsRange), sql: \(sql)")
        // Same swap as `scanBindVars`: `matches(in:range:)` returns an array
        // we can `break` out of, avoiding the `UnsafeMutablePointer<ObjCBool>`
        // `stop` parameter of `enumerateMatches`.
        for match in regex.matches(in: sql, range: nsRange) {
            guard match.numberOfRanges > 2 else {
                log.sqlparse.debug("no match or less than 3 groups")
                continue
            }
            log.sqlparse.debug("=====================================")
            for i in 0 ..< match.numberOfRanges {
                log.sqlparse.debug("range \(i), \(match.range(at: i)): value: \(sql[Range(match.range(at: i), in: sql) ?? sql.startIndex..<sql.startIndex ])")
            }

            // get first two nonzero-based and nonzero-length ranges - should be type and compound name
            var typeNameRanges = [Range<String.Index>]()
            for i in 0 ..< match.numberOfRanges {
                guard match.range(at: i).lowerBound > 0, match.range(at: i).length > 0 else { continue }
                guard let r = Range(match.range(at: i), in: sql) else { continue }
                typeNameRanges.append(r)
                if typeNameRanges.count > 2 { break }
            }
            // identifying type
            let typeRange = typeNameRanges[0]
            let type = String(sql[typeRange]).trimmingCharacters(in: [" ", "\n", "\t"]).replacingOccurrences(of: "  ", with: " ").uppercased()

            // identifying owner name name
            let nameRange = typeNameRanges[1]
            let maybeName = String(sql[nameRange]).trimmingCharacters(in: [" ", "\n", "\t"])
            let nameComponents = maybeName.split(separator: ".").map {
                // if doublequotes are in the name we should preserve case, otherwise convert to uppercase
                $0.contains("\"") ? String($0.replacingOccurrences(of: "\"", with: "")) : String($0.uppercased())
            }
            guard nameComponents.count < 3 else {
                log.sqlparse.debug("name components are wrong: \(nameComponents, privacy: .public)")
                continue
            }

            // now we have all the details
            if nameComponents.count == 1 {
                ret = (true, StoredProc(owner: nil, name: nameComponents[0], type: type))
            } else {
                ret = (true, StoredProc(owner: nameComponents[0], name: nameComponents[1], type: type))
            }
            break  // first valid CREATE wins
        }
        log.sqlparse.debug("stored proc: \(ret.0, privacy: .public), \(ret.1.debugDescription, privacy: .public)")
        return ret
    }
}


public func md5Hash(_ source: String) -> String {
    // `String.data(using: .utf8)` never returns nil for a valid String, so the
    // coalesce to empty Data is just defensive programming for the type system.
    let data = source.data(using: .utf8) ?? Data()
    // `String(format:_:)` uses C variadic argument passing — `@unsafe` in
    // Swift 6.2's strict-memory-safety mode. The format string is a literal,
    // so misuse is impossible.
    return unsafe Insecure.MD5.hash(data: data).map { String(format: "%02hhx", $0) }.joined()
}


