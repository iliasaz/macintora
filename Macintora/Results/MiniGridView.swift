//
//  MiniGridView.swift
//  Macintora
//
//  Inline, bounded preview of rows returned by a SELECT inside the Script
//  Output pane. Capped by `RowsPreview.defaultRowCap`. Promotion to the
//  main grid (Phase 7) hands the rows to a `ResultViewModel`.
//

import SwiftUI

struct MiniGridView: View {
    let preview: RowsPreview
    var onPromote: (() -> Void)? = nil

    @State private var isExpanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                MiniGridTable(preview: preview)
                if preview.truncated {
                    Text("(showing \(preview.rows.count) row\(preview.rows.count == 1 ? "" : "s") — promote to view all)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let onPromote {
                    Button("Open in full grid", systemImage: "arrow.up.right.square", action: onPromote)
                        .controlSize(.small)
                        .buttonStyle(.borderless)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "tablecells")
                    .foregroundStyle(.secondary)
                Text(rowCountLabel(preview))
                    .font(.callout)
            }
        }
    }
}

private func rowCountLabel(_ preview: RowsPreview) -> String {
    let n = preview.rows.count
    let suffix = preview.truncated ? "+" : ""
    return "\(n)\(suffix) row\(n == 1 && !preview.truncated ? "" : "s")"
}

private struct MiniGridTable: View {
    let preview: RowsPreview

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                MiniGridHeader(columns: preview.columns)
                Divider()
                ForEach(0..<preview.rows.count, id: \.self) { row in
                    MiniGridRow(values: preview.rows[row], isAlternate: row.isMultiple(of: 2))
                    if row < preview.rows.count - 1 {
                        Divider().opacity(0.2)
                    }
                }
            }
            .font(.system(.body, design: .monospaced))
        }
        .frame(maxHeight: 240)
    }
}

private struct MiniGridHeader: View {
    let columns: [String]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<columns.count, id: \.self) { i in
                Text(columns[i])
                    .bold()
                    .frame(minWidth: 80, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.15))
            }
        }
    }
}

private struct MiniGridRow: View {
    let values: [String]
    let isAlternate: Bool
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<values.count, id: \.self) { i in
                Text(values[i])
                    .frame(minWidth: 80, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
        }
        .background(isAlternate ? Color.clear : .secondary.opacity(0.05))
    }
}
