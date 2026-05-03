//
//  QuickViewTableView.swift
//  Macintora
//
//  Quick View popover content for a table or view: header strip, columns
//  list, expandable Indexes / Triggers sections, and (for views) a "View
//  SQL" disclosure with the underlying SELECT text.
//

import SwiftUI

struct QuickViewTableView: View {
    let payload: TableDetailPayload
    let openInBrowserAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            QuickViewTableHeader(payload: payload,
                                 openInBrowserAction: openInBrowserAction)
            QuickViewTableColumnsList(columns: payload.columns,
                                      highlightedColumn: payload.highlightedColumn)
            if !payload.indexes.isEmpty {
                QuickViewTableSection(title: "Indexes (\(payload.indexes.count))") {
                    QuickViewIndexList(indexes: payload.indexes)
                }
            }
            if !payload.triggers.isEmpty {
                QuickViewTableSection(title: "Triggers (\(payload.triggers.count))") {
                    QuickViewTriggerList(triggers: payload.triggers)
                }
            }
            if payload.isView, let sql = payload.sqlText, !sql.isEmpty {
                QuickViewTableSection(title: "View SQL") {
                    QuickViewSQLBlock(text: sql)
                }
            }
        }
        .padding(12)
        .frame(width: 520, alignment: .topLeading)
    }
}

private struct QuickViewTableHeader: View {
    let payload: TableDetailPayload
    let openInBrowserAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: payload.isView ? "tablecells.badge.ellipsis" : "tablecells")
                .foregroundStyle(.tint)
            Text("\(payload.owner).\(payload.name)")
                .font(.system(.headline, design: .monospaced))
                .textSelection(.enabled)
            if payload.isView {
                QuickViewChip(label: "View", tone: .accent)
            }
            if payload.isPartitioned {
                QuickViewChip(label: "Partitioned", tone: .secondary)
            }
            if payload.isReadOnly {
                QuickViewChip(label: "Read-Only", tone: .secondary)
            }
            Spacer(minLength: 0)
            if let action = openInBrowserAction {
                Button("Open in Browser", systemImage: "rectangle.portrait.and.arrow.right",
                       action: action)
                    .controlSize(.small)
            }
        }
    }
}

private struct QuickViewTableColumnsList: View {
    let columns: [QuickViewColumn]
    let highlightedColumn: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Columns")
                    .font(.subheadline.bold())
                Spacer()
                Text(columns.count.formatted())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)

            if columns.isEmpty {
                Text("No columns cached for this object.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(columns) { column in
                                QuickViewColumnRow(column: column,
                                                   isHighlighted: column.columnName == highlightedColumn)
                                    .id(column.columnName)
                                Divider()
                                    .opacity(0.5)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    .task(id: highlightedColumn) {
                        if let target = highlightedColumn {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(target, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct QuickViewColumnRow: View {
    let column: QuickViewColumn
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(column.columnName)
                .font(.system(.callout, design: .monospaced))
                .frame(minWidth: 120, alignment: .leading)
                .textSelection(.enabled)
            Text(column.dataTypeFormatted)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 120, alignment: .leading)
                .textSelection(.enabled)
            Group {
                if !column.isNullable {
                    QuickViewChip(label: "NOT NULL", tone: .accent)
                }
                if column.isIdentity {
                    QuickViewChip(label: "Identity", tone: .accent)
                }
                if column.isVirtual {
                    QuickViewChip(label: "Virtual", tone: .accent)
                }
                if column.isHidden {
                    QuickViewChip(label: "Hidden", tone: .secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(isHighlighted ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: 4))
    }
}

private struct QuickViewIndexList: View {
    let indexes: [QuickViewIndex]
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(indexes) { idx in
                HStack(spacing: 8) {
                    Image(systemName: "decrease.indent")
                        .foregroundStyle(.tint)
                    Text(idx.name)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                    if idx.isUnique { QuickViewChip(label: "Unique", tone: .accent) }
                    if !idx.isValid { QuickViewChip(label: "Invalid", tone: .secondary) }
                    Spacer()
                    if let type = idx.type {
                        Text(type)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct QuickViewTriggerList: View {
    let triggers: [QuickViewTrigger]
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(triggers) { trg in
                HStack(spacing: 8) {
                    Image(systemName: "bolt")
                        .foregroundStyle(.tint)
                    Text(trg.name)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                    if !trg.isEnabled {
                        QuickViewChip(label: "Disabled", tone: .secondary)
                    }
                    Spacer()
                    if let event = trg.event {
                        Text(event)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct QuickViewSQLBlock: View {
    let text: String
    var body: some View {
        ScrollView(.vertical) {
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(maxHeight: 220)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 6))
    }
}

struct QuickViewTableSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                    Text(title)
                        .font(.subheadline.bold())
                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if isExpanded {
                content
                    .padding(.leading, 4)
            }
        }
    }
}
