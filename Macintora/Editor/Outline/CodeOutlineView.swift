//
//  CodeOutlineView.swift
//  Macintora
//
//  A reusable code-outline rail: a quick-filter bar over a grouped, navigable
//  list of the PL/SQL symbols defined in `source` (procedures, functions,
//  top-level variables & constants), extracted from the bundled tree-sitter
//  grammar. Clicking a symbol writes its identifier range into `selection`; the
//  host editor (`MacintoraEditor`) selects it and scrolls it near the top.
//
//  Self-contained on purpose — the DB Browser source viewer uses it now, and
//  the worksheet editor can drop it in later without an API change. The caller
//  owns placement/resize/collapse (e.g. an `HSplitView` + a toolbar toggle).
//

import SwiftUI
import STPluginNeon  // SwiftTreeSitter for the optional pre-built tree

struct CodeOutlineView: View {
    @Binding var source: String
    @Binding var selection: Range<String.Index>
    /// Optional already-parsed tree for the initial pass; later edits re-parse.
    var tree: SwiftTreeSitter.Tree?
    var accessibilityIdentifier: String = "outline.code"
    /// Fired after `navigate(to:)` has set `selection`. Hosts use it to bump
    /// the editor's reveal-generation counter so that *repeat* clicks on the
    /// same row still force a scroll-and-flash even though `selection` didn't
    /// change.
    var onNavigate: ((CodeSymbol) -> Void)?

    init(source: Binding<String>,
         selection: Binding<Range<String.Index>>,
         tree: SwiftTreeSitter.Tree? = nil,
         accessibilityIdentifier: String = "outline.code",
         onNavigate: ((CodeSymbol) -> Void)? = nil) {
        self._source = source
        self._selection = selection
        self.tree = tree
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onNavigate = onNavigate
    }

    @State private var model = CodeOutlineModel()
    @State private var refreshTask: Task<Void, Never>?
    @FocusState private var filterFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            CodeOutlineSearchBar(filterText: $model.filterText,
                                 kindFilter: $model.kindFilter,
                                 availableFilters: model.availableFilters,
                                 focused: $filterFocused)
            Divider()
            symbolList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // Off-screen control so ⌘L focuses the filter even without a menu item.
            Button("Filter Symbols") { filterFocused = true }
                .keyboardShortcut("l", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .task { model.refresh(from: source, tree: tree) }
        .onChange(of: source) { scheduleRefresh() }
        .onChange(of: selection) {
            model.caretUTF16Offset = selection.lowerBound.utf16Offset(in: source)
        }
    }

    @ViewBuilder
    private var symbolList: some View {
        if model.hasNoSymbols {
            // Keep the same shape as the populated rail (the search bar above is
            // still there) rather than a tiny "empty" placeholder.
            List {
                Text("No symbols detected in this source.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier(accessibilityIdentifier)
        } else if model.sections.isEmpty {
            ContentUnavailableView.search(text: model.filterText)
        } else {
            List {
                ForEach(model.sections) { section in
                    Section {
                        ForEach(section.symbols) { symbol in
                            CodeOutlineRow(symbol: symbol, action: { navigate(to: symbol) })
                        }
                    } header: {
                        CodeOutlineSectionHeader(kind: section.kind, count: section.symbols.count)
                    }
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier(accessibilityIdentifier)
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        let current = source
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            model.refresh(from: current)
        }
    }

    private func navigate(to symbol: CodeSymbol) {
        guard let range = EditorSelectionBridge.range(forUTF16: symbol.nameRange, in: source) else { return }
        selection = range
        onNavigate?(symbol)
    }
}

// MARK: - Search bar

private struct CodeOutlineSearchBar: View {
    @Binding var filterText: String
    @Binding var kindFilter: CodeOutlineModel.KindFilter
    let availableFilters: [CodeOutlineModel.KindFilter]
    @FocusState.Binding var focused: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Filter symbols", text: $filterText)
                    .textFieldStyle(.plain)
                    .focused($focused)
                if !filterText.isEmpty {
                    Button("Clear filter", systemImage: "xmark.circle.fill") { filterText = "" }
                        .buttonStyle(.plain)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))

            if availableFilters.count > 1 {
                Picker("Scope", selection: $kindFilter) {
                    ForEach(availableFilters) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }
        }
        .padding(8)
    }
}

// MARK: - Section header

private struct CodeOutlineSectionHeader: View {
    let kind: CodeSymbol.Kind
    let count: Int

    var body: some View {
        HStack {
            Label(kind.sectionTitle, systemImage: kind.systemImage)
                .font(.caption.bold())
            Spacer()
            Text(count.formatted())
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Row

private struct CodeOutlineRow: View {
    let symbol: CodeSymbol
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    KindBadge(kind: symbol.kind)
                    Text(symbol.name)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(symbol.line.formatted(.number.grouping(.never)))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
                if let detail = symbol.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(symbol.isDeclaration ? "Declaration · line \(symbol.line)" : "Line \(symbol.line)")
    }
}

// MARK: - Kind badge

private struct KindBadge: View {
    let kind: CodeSymbol.Kind

    var body: some View {
        Text(kind.badge)
            .font(.caption2)
            .bold()
            .kerning(0.4)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(kind.tint.opacity(0.16), in: .rect(cornerRadius: 3))
            .foregroundStyle(kind.tint)
            .accessibilityLabel(kind.sectionTitle)
    }
}
