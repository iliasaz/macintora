//
//  QuickViewContent.swift
//  Macintora
//
//  Root SwiftUI view consumed by `QuickViewPresenter`'s NSHostingController.
//  Switches on the payload kind so the popover always renders one of:
//    * column mini-popover
//    * table / view detail
//    * package / type detail
//    * standalone procedure / function detail
//    * "not cached" placeholder when the cache holds no row
//
//  Receives a single `openInBrowserAction` closure that the host wires up
//  for issue #13 (DB Browser pre-fetch). When `nil`, the footer button is
//  hidden (read-only viewers, previews, etc.).
//

import SwiftUI

struct QuickViewContent: View {
    let payload: QuickViewPayload
    let openInBrowserAction: (() -> Void)?

    var body: some View {
        switch payload {
        case .table(let table):
            QuickViewTableView(payload: table,
                               openInBrowserAction: openInBrowserAction)
        case .packageOrType(let pkg):
            QuickViewPackageView(payload: pkg,
                                 openInBrowserAction: openInBrowserAction)
        case .procedure(let proc):
            QuickViewProcedureView(payload: proc,
                                   openInBrowserAction: openInBrowserAction)
        case .column(let col):
            QuickViewColumnView(payload: col,
                                openInBrowserAction: openInBrowserAction)
        case .unknownObject(let unknown):
            QuickViewUnknownObjectView(payload: unknown,
                                       openInBrowserAction: openInBrowserAction)
        case .notCached(let reference):
            QuickViewNotCachedView(reference: reference,
                                   openInBrowserAction: openInBrowserAction)
        }
    }
}

struct QuickViewUnknownObjectView: View {
    let payload: UnknownObjectPayload
    let openInBrowserAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "questionmark.square")
                    .foregroundStyle(.tint)
                Text("\(payload.owner).\(payload.name)")
                    .font(.system(.headline, design: .monospaced))
                    .textSelection(.enabled)
                QuickViewChip(label: payload.objectType, tone: .accent)
                if !payload.isValid {
                    QuickViewChip(label: "Invalid", tone: .secondary)
                }
                Spacer()
            }
            if let lastDDL = payload.lastDDLDate {
                Text("Last DDL: \(lastDDL.formatted(date: .abbreviated, time: .shortened))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                if let action = openInBrowserAction {
                    Button("Open in Browser",
                           systemImage: "rectangle.portrait.and.arrow.right",
                           action: action)
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(width: 360, alignment: .topLeading)
    }
}

struct QuickViewNotCachedView: View {
    let reference: ResolvedDBReference
    let openInBrowserAction: (() -> Void)?

    private var displayName: String {
        switch reference {
        case .schemaObject(let owner, let name):
            return owner.map { "\($0).\(name)" } ?? name
        case .packageMember(let owner, let pkg, let member):
            let prefix = owner.map { "\($0)." } ?? ""
            return "\(prefix)\(pkg).\(member)"
        case .column(let owner, let table, let column):
            let prefix = owner.map { "\($0)." } ?? ""
            return "\(prefix)\(table).\(column)"
        case .unresolved:
            return "—"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
                Text(displayName)
                    .font(.system(.headline, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
            }
            Text("Not cached for this connection.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Refresh the database cache from the Browser to populate Quick View.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            HStack {
                Spacer()
                if let action = openInBrowserAction {
                    Button("Open in Browser",
                           systemImage: "rectangle.portrait.and.arrow.right",
                           action: action)
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(width: 360, alignment: .topLeading)
    }
}
