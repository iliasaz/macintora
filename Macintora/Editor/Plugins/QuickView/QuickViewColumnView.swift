//
//  QuickViewColumnView.swift
//  Macintora
//
//  Compact mini-popover for a single column reference. Shows name + type +
//  nullable + default + a chip row for derived (identity / virtual / hidden).
//  Sized small (~280×170) so it doesn't fight the table popover for space.
//

import SwiftUI

struct QuickViewColumnView: View {
    let payload: ColumnDetailPayload
    let openInBrowserAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "list.bullet")
                    .foregroundStyle(.tint)
                Text(payload.column.columnName)
                    .font(.system(.headline, design: .monospaced))
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                Text(payload.column.dataTypeFormatted)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            QuickViewColumnFlagsRow(column: payload.column)

            QuickViewColumnDetailsBlock(column: payload.column)

            HStack {
                Text("\(payload.tableOwner).\(payload.tableName)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
                if let openInBrowserAction {
                    Button("Open Table…", systemImage: "tablecells", action: openInBrowserAction)
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(width: 320, alignment: .topLeading)
    }
}

private struct QuickViewColumnFlagsRow: View {
    let column: QuickViewColumn

    var body: some View {
        HStack(spacing: 6) {
            QuickViewChip(label: column.isNullable ? "NULL" : "NOT NULL",
                          tone: column.isNullable ? .secondary : .accent)
            if column.isIdentity {
                QuickViewChip(label: "Identity", tone: .accent)
            }
            if column.isVirtual {
                QuickViewChip(label: "Virtual", tone: .accent)
            }
            if column.isHidden {
                QuickViewChip(label: "Hidden", tone: .secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct QuickViewColumnDetailsBlock: View {
    let column: QuickViewColumn

    var body: some View {
        if let defaultValue = column.defaultValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !defaultValue.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(column.isVirtual ? "Expression" : "Default")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView(.vertical) {
                    Text(defaultValue)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 80)
            }
        }
    }
}

enum QuickViewChipTone {
    case accent, secondary
}

struct QuickViewChip: View {
    let label: String
    let tone: QuickViewChipTone

    var body: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background, in: .capsule)
            .foregroundStyle(foreground)
    }

    private var background: AnyShapeStyle {
        switch tone {
        case .accent: AnyShapeStyle(.tint.opacity(0.15))
        case .secondary: AnyShapeStyle(.quaternary)
        }
    }

    private var foreground: AnyShapeStyle {
        switch tone {
        case .accent: AnyShapeStyle(.tint)
        case .secondary: AnyShapeStyle(.secondary)
        }
    }
}

#Preview("Plain column") {
    QuickViewColumnView(
        payload: ColumnDetailPayload(
            tableOwner: "HR",
            tableName: "EMPLOYEES",
            column: QuickViewColumn(
                columnID: 1,
                columnName: "SALARY",
                dataType: "NUMBER",
                dataTypeFormatted: "NUMBER(10,2)",
                isNullable: false,
                defaultValue: nil,
                isIdentity: false,
                isVirtual: false,
                isHidden: false)),
        openInBrowserAction: {})
}

#Preview("Virtual + identity") {
    QuickViewColumnView(
        payload: ColumnDetailPayload(
            tableOwner: "HR",
            tableName: "EMPLOYEES",
            column: QuickViewColumn(
                columnID: 8,
                columnName: "TOTAL_COMP",
                dataType: "NUMBER",
                dataTypeFormatted: "NUMBER(12,2)",
                isNullable: true,
                defaultValue: "salary + nvl(commission,0)",
                isIdentity: false,
                isVirtual: true,
                isHidden: false)),
        openInBrowserAction: {})
}
