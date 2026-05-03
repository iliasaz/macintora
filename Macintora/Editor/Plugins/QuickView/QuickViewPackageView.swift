//
//  QuickViewPackageView.swift
//  Macintora
//
//  Quick View popover content for a package or user-defined type. Lists
//  member procedures with collapsible argument signatures. The full source
//  body is intentionally not shown here — too long for a popover; the "Open
//  in Browser" button is the path to that.
//

import SwiftUI

struct QuickViewPackageView: View {
    let payload: PackageDetailPayload
    let openInBrowserAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            QuickViewPackageHeader(payload: payload,
                                   openInBrowserAction: openInBrowserAction)
            if payload.procedures.isEmpty {
                QuickViewPackageEmptyState(objectType: payload.objectType,
                                           specSource: payload.specSource)
            } else {
                QuickViewPackageProceduresList(procedures: payload.procedures)
            }
        }
        .padding(12)
        .frame(width: 520, alignment: .topLeading)
    }
}

private struct QuickViewPackageHeader: View {
    let payload: PackageDetailPayload
    let openInBrowserAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: payload.objectType == "TYPE"
                  ? "t.square"
                  : "ellipsis.curlybraces")
                .foregroundStyle(.tint)
            Text("\(payload.owner).\(payload.name)")
                .font(.system(.headline, design: .monospaced))
                .textSelection(.enabled)
            QuickViewChip(label: payload.objectType, tone: .accent)
            if !payload.isValid {
                QuickViewChip(label: "Invalid", tone: .secondary)
            }
            Spacer(minLength: 0)
            if let action = openInBrowserAction {
                Button("Open in Browser",
                       systemImage: "rectangle.portrait.and.arrow.right",
                       action: action)
                    .controlSize(.small)
            }
        }
    }
}

private struct QuickViewPackageEmptyState: View {
    let objectType: String
    let specSource: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No procedures or functions cached.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let spec = specSource, !spec.isEmpty {
                QuickViewSQLBlock(text: spec)
            }
        }
    }
}

private struct QuickViewPackageProceduresList: View {
    let procedures: [QuickViewPackageProcedure]

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(procedures) { proc in
                    QuickViewPackageProcedureRow(procedure: proc)
                    Divider().opacity(0.4)
                }
            }
        }
        .frame(maxHeight: 320)
    }
}

private struct QuickViewPackageProcedureRow: View {
    let procedure: QuickViewPackageProcedure
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: procedure.kind == "FUNCTION"
                          ? "f.cursive"
                          : "curlybraces")
                        .foregroundStyle(.tint)
                    Text(procedure.name)
                        .font(.system(.callout, design: .monospaced))
                    if let overload = procedure.overload, !overload.isEmpty {
                        Text("(#\(overload))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if let returnType = procedure.returnType {
                        Text("→ \(returnType)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer()
                    Text("\(procedure.parameters.count) param\(procedure.parameters.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
            }
            .buttonStyle(.plain)
            if isExpanded {
                if procedure.parameters.isEmpty {
                    Text("(no parameters)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 30)
                        .padding(.bottom, 4)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(procedure.parameters) { arg in
                            QuickViewArgumentRow(argument: arg)
                                .padding(.leading, 24)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }
}
