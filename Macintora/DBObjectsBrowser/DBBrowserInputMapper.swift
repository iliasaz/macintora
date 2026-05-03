//
//  DBBrowserInputMapper.swift
//  Macintora
//
//  Converts a `ResolvedDBReference` (produced by `ObjectAtCursorResolver`) into
//  a `DBCacheInputValue` suitable for opening the DB Browser pre-focused on the
//  cursor object.
//
//  Mapping rules:
//  - `.schemaObject`   → search for the named object, owner as owner filter
//  - `.packageMember`  → open the parent package; Details tab (shows source)
//  - `.column`         → open the parent table; Details tab (shows columns)
//  - `.unresolved`     → no-op: returns a bare `DBCacheInputValue` with no
//                         pre-selection so the browser still opens
//

import Foundation

enum DBBrowserInputMapper {
    /// Builds a `DBCacheInputValue` that pre-focuses the DB Browser on the
    /// object described by `reference`, using `mainConnection` as the target.
    static func inputValue(
        from reference: ResolvedDBReference,
        mainConnection: MainConnection
    ) -> DBCacheInputValue {
        switch reference {

        case .schemaObject(let owner, let name):
            return DBCacheInputValue(
                mainConnection: mainConnection,
                selectedOwner: owner,
                selectedObjectName: name,
                selectedObjectType: nil,
                initialDetailTab: .details
            )

        case .packageMember(let pkgOwner, let pkgName, _):
            // Navigate to the parent package, not the individual member.
            return DBCacheInputValue(
                mainConnection: mainConnection,
                selectedOwner: pkgOwner,
                selectedObjectName: pkgName,
                selectedObjectType: OracleObjectType.package.rawValue,
                initialDetailTab: .details
            )

        case .column(let tableOwner, let tableName, _):
            // Navigate to the parent table; Details tab shows column list.
            return DBCacheInputValue(
                mainConnection: mainConnection,
                selectedOwner: tableOwner,
                selectedObjectName: tableName,
                selectedObjectType: OracleObjectType.table.rawValue,
                initialDetailTab: .details
            )

        case .unresolved:
            return DBCacheInputValue(mainConnection: mainConnection)
        }
    }
}
