//
//  PackageProceduresListView.swift
//  Macintora
//

import SwiftUI
import CoreData

struct PackageProceduresListView: View {
    @FetchRequest private var procedures: FetchedResults<DBCacheProcedure>
    @FetchRequest private var arguments: FetchedResults<DBCacheProcedureArgument>

    init(dbObject: DBCacheObject) {
        let predicate = NSPredicate(format: "owner_ = %@ and objectName_ = %@", dbObject.owner, dbObject.name)
        _procedures = FetchRequest<DBCacheProcedure>(
            sortDescriptors: [
                NSSortDescriptor(key: "procedureName_", ascending: true),
                NSSortDescriptor(key: "overload_", ascending: true)
            ],
            predicate: predicate
        )
        _arguments = FetchRequest<DBCacheProcedureArgument>(
            sortDescriptors: [
                NSSortDescriptor(key: "procedureName_", ascending: true),
                NSSortDescriptor(key: "overload_", ascending: true),
                NSSortDescriptor(key: "sequence", ascending: true)
            ],
            predicate: predicate
        )
    }

    private var groups: [ProcedureGroup] {
        // Build (procedureName, overload, subprogramId) groups, drop the
        // SUBPROGRAM_ID = 0 package-itself row (procedureName == "" or equal
        // to package name with no procedureName).
        var byKey: [GroupKey: ProcedureGroup] = [:]
        for proc in procedures {
            let procName = proc.procedureName_ ?? ""
            guard !procName.isEmpty else { continue }
            // Skip the package self row: ALL_PROCEDURES emits a row with
            // PROCEDURE_NAME = NULL for the package itself; once stored in
            // CoreData, that field is nil and filtered above. The remaining
            // edge case is a row where PROCEDURE_NAME equals the package name
            // (rare but possible for a standalone listing) — keep it.
            let key = GroupKey(name: procName, overload: proc.overload_ ?? "", subprogramId: proc.subprogramId)
            if byKey[key] == nil {
                byKey[key] = ProcedureGroup(
                    key: key,
                    objectType: proc.objectType_ ?? "",
                    isPipelined: proc.isPipelined,
                    isDeterministic: proc.isDeterministic,
                    parameters: [],
                    returnType: nil
                )
            }
        }
        for arg in arguments {
            guard arg.dataLevel == 0 else { continue }
            let procName = arg.procedureName_ ?? ""
            guard !procName.isEmpty else { continue }
            // Match the matching procedure group by (name, overload). The
            // subprogramId may differ across schemas/overloads, so we key
            // primarily by name + overload and fold subprogramId in if a
            // match exists.
            let candidate = byKey.keys.first {
                $0.name == procName && $0.overload == (arg.overload_ ?? "")
            }
            guard let key = candidate else { continue }
            if arg.position == 0 && arg.argumentName_ == nil {
                byKey[key]?.returnType = arg.dataType_
            } else if arg.position > 0 {
                byKey[key]?.parameters.append(arg)
            }
        }
        return byKey.values.sorted { lhs, rhs in
            if lhs.key.name != rhs.key.name { return lhs.key.name < rhs.key.name }
            return lhs.key.overload < rhs.key.overload
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if procedures.isEmpty {
                Text("No procedures or functions cached for this object.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List {
                    ForEach(groups) { group in
                        Section {
                            if group.parameters.isEmpty {
                                Text("(no parameters)")
                                    .foregroundStyle(.secondary)
                                    .font(Font(NSFont(name: "Source Code Pro", size: NSFont.systemFontSize)!))
                            } else {
                                ForEach(group.parameters) { arg in
                                    ArgumentRow(argument: arg)
                                }
                            }
                        } header: {
                            ProcedureHeader(group: group)
                        }
                    }
                }
                .listStyle(.inset)
                .font(Font(NSFont(name: "Source Code Pro", size: NSFont.systemFontSize)!))
            }
        }
        .padding()
        .overlay(
            RoundedRectangle(cornerRadius: 25)
                .stroke(.quaternary, lineWidth: 2)
        )
        .padding([.top, .leading, .trailing])
    }
}

private struct GroupKey: Hashable {
    let name: String
    let overload: String
    let subprogramId: Int32
}

private struct ProcedureGroup: Identifiable {
    let key: GroupKey
    let objectType: String
    let isPipelined: Bool
    let isDeterministic: Bool
    var parameters: [DBCacheProcedureArgument]
    var returnType: String?

    var id: GroupKey { key }
    var isFunction: Bool { returnType != nil }
}

private struct ProcedureHeader: View {
    let group: ProcedureGroup

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: group.isFunction ? "f.cursive" : "curlybraces")
                .foregroundStyle(.tint)
            Text(group.key.name)
                .bold()
            if !group.key.overload.isEmpty {
                Text("#\(group.key.overload)")
                    .foregroundStyle(.secondary)
            }
            if let returnType = group.returnType {
                Text("→ \(returnType)")
                    .foregroundStyle(.secondary)
            }
            if group.isPipelined {
                Text("[pipelined]").foregroundStyle(.secondary)
            }
            if group.isDeterministic {
                Text("[deterministic]").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(Font(NSFont(name: "Source Code Pro", size: NSFont.systemFontSize)!))
    }
}

private struct ArgumentRow: View {
    let argument: DBCacheProcedureArgument

    var body: some View {
        HStack(spacing: 6) {
            Text(argument.argumentName_ ?? "(positional)")
                .foregroundStyle(.primary)
            Text(":")
                .foregroundStyle(.secondary)
            Text(argument.dataType_ ?? "")
                .foregroundStyle(.secondary)
            Text("[\(argument.inOut_ ?? "IN")]")
                .foregroundStyle(.tertiary)
            if argument.defaulted, let value = argument.defaultValue_, !value.isEmpty {
                Text("DEFAULT \(value)")
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
        }
    }
}
