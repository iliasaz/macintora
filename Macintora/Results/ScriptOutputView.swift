//
//  ScriptOutputView.swift
//  Macintora
//
//  SwiftUI view for the Script Output pane. Renders the `ScriptOutputModel`
//  as a streaming list of typed entries — one per executed unit, plus
//  cancelled/info notes. Phase 4 wires this in alongside the runner; Phase
//  5 hooks `onRevealSource` to the editor.
//

import SwiftUI

struct ScriptOutputView: View {
    @Bindable var model: ScriptOutputModel
    /// Phase 5 callback: navigate from a failed entry back to the editor
    /// using a UTF-16 range in the original script source.
    var onRevealSource: ((Range<Int>) -> Void)? = nil
    /// Phase 7 callback: promote a SELECT preview to the main grid.
    var onPromotePreview: ((SucceededEntry) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScriptOutputHeader(model: model)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.entries) { entry in
                        ScriptOutputRow(
                            entry: entry,
                            onRevealSource: onRevealSource,
                            onPromotePreview: onPromotePreview
                        )
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}

private struct ScriptOutputHeader: View {
    @Bindable var model: ScriptOutputModel

    var body: some View {
        HStack(spacing: 8) {
            if model.isRunning {
                ProgressView()
                    .controlSize(.small)
                if let i = model.currentUnitIndex {
                    Text("Running \(i + 1) of \(model.totalUnits)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if !model.entries.isEmpty {
                Text("\(model.entries.count) entr\(model.entries.count == 1 ? "y" : "ies")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Clear", systemImage: "trash") {
                model.clear()
            }
            .controlSize(.small)
            .labelStyle(.iconOnly)
            .disabled(model.entries.isEmpty || model.isRunning)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}

private struct ScriptOutputRow: View {
    let entry: ScriptOutputEntry
    var onRevealSource: ((Range<Int>) -> Void)?
    var onPromotePreview: ((SucceededEntry) -> Void)?

    var body: some View {
        switch entry {
        case .directive(let e): DirectiveRow(entry: e)
        case .prompt(let e): PromptRow(entry: e)
        case .succeeded(let e):
            SucceededRow(entry: e, onPromote: onPromotePreview.map { cb in { cb(e) } })
        case .failed(let e):
            FailedRow(entry: e, onRevealSource: onRevealSource)
        case .note(let e): NoteRow(entry: e)
        }
    }
}

private struct DirectiveRow: View {
    let entry: DirectiveEntry
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "gear")
                .foregroundStyle(.secondary)
            Text(entry.text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

private struct PromptRow: View {
    let entry: PromptEntry
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.bubble")
                .foregroundStyle(.secondary)
            Text(entry.message)
                .font(.system(.body))
            Spacer()
        }
    }
}

private struct SucceededRow: View {
    let entry: SucceededEntry
    var onPromote: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(summaryLine(entry))
                    .font(.callout)
                Spacer()
                Text(entry.elapsed.formatted(.units(allowed: [.milliseconds, .seconds])))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(entry.text)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
            if let preview = entry.preview {
                MiniGridView(preview: preview, onPromote: onPromote)
            }
            if !entry.dbmsOutput.isEmpty {
                DbmsOutputBlock(lines: entry.dbmsOutput)
            }
        }
    }
}

private func summaryLine(_ entry: SucceededEntry) -> String {
    if let n = entry.rowCount {
        return "\(n) row\(n == 1 ? "" : "s")"
    }
    switch entry.kind {
    case .plsqlBlock: return "PL/SQL block executed"
    case .sqlplus:    return "OK"
    case .sql:        return "Done"
    }
}

private struct FailedRow: View {
    let entry: FailedEntry
    var onRevealSource: ((Range<Int>) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                if let code = entry.oracleErrorCode {
                    Text("ORA-\(code)")
                        .font(.callout)
                        .bold()
                        .monospacedDigit()
                } else {
                    Text("Error").font(.callout).bold()
                }
                Spacer()
                Text(entry.elapsed.formatted(.units(allowed: [.milliseconds, .seconds])))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let range = entry.originalUTF16Range, let onRevealSource {
                    Button("Reveal", systemImage: "arrow.up.left.square") {
                        onRevealSource(range)
                    }
                    .controlSize(.small)
                    .labelStyle(.iconOnly)
                }
            }
            Text(entry.message)
                .foregroundStyle(.red)
                .textSelection(.enabled)
            Text(entry.text)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
        }
    }
}

private struct NoteRow: View {
    let entry: NoteEntry
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName(entry.kind))
                .foregroundStyle(iconColor(entry.kind))
            Text(entry.text)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

private func iconName(_ kind: NoteEntry.Kind) -> String {
    switch kind {
    case .cancelled: return "stop.circle"
    case .info:      return "info.circle"
    case .warning:   return "exclamationmark.triangle"
    }
}

private func iconColor(_ kind: NoteEntry.Kind) -> Color {
    switch kind {
    case .cancelled: return .secondary
    case .info:      return .secondary
    case .warning:   return .orange
    }
}

private struct DbmsOutputBlock: View {
    let lines: [String]
    @State private var isExpanded: Bool = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ScrollView(.vertical) {
                Text(lines.joined(separator: "\n"))
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.08))
            }
            .frame(maxHeight: 160)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
                Text("DBMS_OUTPUT (\(lines.count) line\(lines.count == 1 ? "" : "s"))")
                    .font(.callout)
            }
        }
    }
}

#Preview {
    let model = ScriptOutputModel()
    model.beginRun(totalUnits: 3)
    model.append(.directive(.init(id: UUID(), text: "SET SERVEROUTPUT ON", elapsed: .zero)))
    model.append(.succeeded(.init(
        id: UUID(),
        unitIndex: 1,
        text: "SELECT * FROM dual",
        kind: .sql,
        elapsed: .milliseconds(42),
        rowCount: 1,
        dbmsOutput: [],
        preview: .init(columns: ["DUMMY"], rows: [["X"]], truncated: false)
    )))
    model.append(.failed(.init(
        id: UUID(),
        unitIndex: 2,
        text: "SELECT * FROM nonexistent",
        kind: .sql,
        elapsed: .milliseconds(8),
        message: "ORA-00942: table or view does not exist",
        oracleErrorCode: 942,
        originalUTF16Range: 0..<25
    )))
    model.finishRun()
    return ScriptOutputView(model: model)
        .frame(width: 700, height: 400)
}
