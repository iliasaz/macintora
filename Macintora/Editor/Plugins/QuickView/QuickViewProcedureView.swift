//
//  QuickViewProcedureView.swift
//  Macintora
//
//  Single-procedure / single-function popover content. Renders the call
//  signature, parameters, and (for functions) the return type.
//

import SwiftUI

struct QuickViewProcedureView: View {
    let payload: ProcedureDetailPayload
    let openInBrowserAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            QuickViewProcedureHeader(payload: payload,
                                     openInBrowserAction: openInBrowserAction)
            QuickViewProcedureSignature(payload: payload)
        }
        .padding(12)
        .frame(width: 480, alignment: .topLeading)
    }
}

private struct QuickViewProcedureHeader: View {
    let payload: ProcedureDetailPayload
    let openInBrowserAction: (() -> Void)?

    private var qualifiedName: String {
        var parts: [String] = [payload.owner]
        if let pkg = payload.packageName, !pkg.isEmpty {
            parts.append(pkg)
        }
        parts.append(payload.name)
        return parts.joined(separator: ".")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: payload.kind == "FUNCTION" ? "f.cursive" : "curlybraces")
                .foregroundStyle(.tint)
            Text(qualifiedName)
                .font(.system(.headline, design: .monospaced))
                .textSelection(.enabled)
            if let overload = payload.overload, !overload.isEmpty {
                QuickViewChip(label: "Overload \(overload)", tone: .secondary)
            }
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

struct QuickViewProcedureSignature: View {
    let payload: ProcedureDetailPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if payload.parameters.isEmpty {
                Text("(no parameters)")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(payload.parameters) { arg in
                            QuickViewArgumentRow(argument: arg)
                            Divider().opacity(0.4)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
            if let returnType = payload.returnType {
                Divider()
                HStack {
                    Image(systemName: "return")
                        .foregroundStyle(.secondary)
                    Text("RETURN")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(returnType)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
    }
}

struct QuickViewArgumentRow: View {
    let argument: QuickViewProcedureArgument

    var body: some View {
        HStack(spacing: 8) {
            Text(argument.inOut)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 36, alignment: .leading)
            Text(argument.name ?? "")
                .font(.system(.callout, design: .monospaced))
                .frame(minWidth: 140, alignment: .leading)
                .textSelection(.enabled)
            Text(argument.dataType)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 140, alignment: .leading)
                .textSelection(.enabled)
            if argument.defaulted {
                Text("DEFAULT \(argument.defaultValue ?? "")")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
    }
}
