//
//  QuickViewPayload.swift
//  Macintora
//
//  Sendable view-models returned by the cache-side fetchers and consumed by
//  the `QuickViewContent` SwiftUI tree. Plain structs (never `NSManagedObject`)
//  so results can cross the `CompletionDataSource` actor boundary safely.
//

import Foundation

/// What `QuickViewController` hands to `QuickViewContent` after a successful
/// cache fetch. Drives which detail subview renders.
enum QuickViewPayload: Sendable, Equatable {
    case table(TableDetailPayload)
    case packageOrType(PackageDetailPayload)
    case procedure(ProcedureDetailPayload)
    case column(ColumnDetailPayload)
    case unknownObject(UnknownObjectPayload)
    case notCached(reference: ResolvedDBReference)
}

// MARK: - Table / view

struct TableDetailPayload: Sendable, Equatable {
    let owner: String
    let name: String
    let isView: Bool
    let isEditioning: Bool
    let isReadOnly: Bool
    let isPartitioned: Bool
    let numRows: Int64?
    let lastAnalyzed: Date?
    let sqlText: String?       // populated for views
    let columns: [QuickViewColumn]
    let indexes: [QuickViewIndex]
    let triggers: [QuickViewTrigger]
    /// When the user invoked Quick View from a column reference, this carries
    /// the column name to scroll/highlight in the columns list. nil otherwise.
    let highlightedColumn: String?
}

struct QuickViewColumn: Sendable, Equatable, Identifiable {
    var id: String { columnName }
    let columnID: Int32
    let columnName: String
    let dataType: String
    /// Pre-formatted Oracle-style type string e.g. `VARCHAR2(120)` or `NUMBER(10,2)`.
    let dataTypeFormatted: String
    let isNullable: Bool
    let defaultValue: String?
    let isIdentity: Bool
    let isVirtual: Bool
    let isHidden: Bool
}

struct QuickViewIndex: Sendable, Equatable, Identifiable {
    var id: String { "\(owner).\(name)" }
    let owner: String
    let name: String
    let type: String?
    let isUnique: Bool
    let isValid: Bool
}

struct QuickViewTrigger: Sendable, Equatable, Identifiable {
    var id: String { "\(owner).\(name)" }
    let owner: String
    let name: String
    let event: String?
    let isEnabled: Bool
}

// MARK: - Package / type

struct PackageDetailPayload: Sendable, Equatable {
    let owner: String
    let name: String
    /// `"PACKAGE"`, `"TYPE"`, etc. — drives the header label.
    let objectType: String
    let isValid: Bool
    /// Spec source. Body is intentionally omitted from Quick View — too long
    /// for a popover. The "Open in Browser" button is the path to full source.
    let specSource: String?
    let procedures: [QuickViewPackageProcedure]
}

struct QuickViewPackageProcedure: Sendable, Equatable, Identifiable {
    var id: String { "\(name)#\(overload ?? "")" }
    let name: String
    let kind: String   // "PROCEDURE" | "FUNCTION"
    let overload: String?
    let returnType: String?
    let parameters: [QuickViewProcedureArgument]
}

struct QuickViewProcedureArgument: Sendable, Equatable, Identifiable {
    var id: Int { sequence }
    let sequence: Int
    let position: Int
    let name: String?
    let dataType: String
    let inOut: String        // "IN" | "OUT" | "IN/OUT"
    let defaulted: Bool
    let defaultValue: String?
}

// MARK: - Standalone procedure / function

struct ProcedureDetailPayload: Sendable, Equatable {
    let owner: String
    /// Either the standalone proc/function name, or the package member name.
    let name: String
    /// Non-nil and equal to the package name when the procedure is a member.
    let packageName: String?
    let kind: String   // "PROCEDURE" | "FUNCTION"
    let overload: String?
    let returnType: String?
    let parameters: [QuickViewProcedureArgument]
    let isValid: Bool
}

// MARK: - Column

struct ColumnDetailPayload: Sendable, Equatable {
    let tableOwner: String
    let tableName: String
    let column: QuickViewColumn
}

// MARK: - Catch-all (TYPE, INDEX, TRIGGER without further detail)

struct UnknownObjectPayload: Sendable, Equatable {
    let owner: String
    let name: String
    let objectType: String
    let isValid: Bool
    let lastDDLDate: Date?
}
