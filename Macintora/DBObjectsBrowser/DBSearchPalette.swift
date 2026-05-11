//
//  DBSearchPalette.swift
//  Macintora
//
//  ⌘K command palette for the DB Browser (v2 design, Search variant A):
//  a centered Spotlight-style sheet — substring match over object names,
//  type-scoped, recents up top, keyboard-driven. ↩ reveals the object in
//  the current window, ⌘↩ opens it in a new one.
//

import SwiftUI
import CoreData

/// Per-TNS "recently opened object" list. Small enough for UserDefaults; the
/// (owner, name, type) keys are stable across cache rebuilds.
enum DBBrowserRecents {
    private static let storeKey = "dbBrowserRecents"
    private static let cap = 12

    static func record(tns: String, _ key: DBPinnedKey, defaults: UserDefaults = .standard) {
        var dict = defaults.dictionary(forKey: storeKey) as? [String: [String]] ?? [:]
        var list = dict[tns] ?? []
        list.removeAll { $0 == key.encoded }
        list.insert(key.encoded, at: 0)
        if list.count > cap { list = Array(list.prefix(cap)) }
        dict[tns] = list
        defaults.set(dict, forKey: storeKey)
    }

    static func list(tns: String, defaults: UserDefaults = .standard) -> [DBPinnedKey] {
        let dict = defaults.dictionary(forKey: storeKey) as? [String: [String]] ?? [:]
        return (dict[tns] ?? []).compactMap(DBPinnedKey.init(encoded:))
    }
}

private enum SearchScope: String, CaseIterable, Identifiable {
    case all, objects, code
    var id: Self { self }
    var label: String {
        switch self {
        case .all:     "All"
        case .objects: "Objects"
        case .code:    "Code"
        }
    }
    /// Type rawValues this scope restricts to, or nil for "no restriction".
    var typeRawValues: [String]? {
        switch self {
        case .all:     nil
        case .objects: ["TABLE", "VIEW", "INDEX"]
        case .code:    ["PACKAGE", "PROCEDURE", "FUNCTION", "TYPE", "TRIGGER"]
        }
    }
}

struct DBSearchPalette: View {
    let tns: String
    let onReveal: (DBCacheObject) -> Void
    let onOpenInNewWindow: (DBCacheObject) -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var scope: SearchScope = .all
    @State private var matches: [DBCacheObject] = []
    @State private var recents: [DBCacheObject] = []
    @State private var highlighted = 0
    @FocusState private var fieldFocused: Bool

    private var rows: [DBCacheObject] { query.isEmpty ? recents : matches }

    var body: some View {
        VStack(spacing: 0) {
            inputRow
            Divider()
            scopeRow
            Divider()
            resultsList
            Divider()
            footerRow
        }
        .frame(width: 560)
        .background {
            // Plain ↩ opens the highlighted row; ⌘↩ opens in a new window.
            Button("") { activate(.newWindow) }
                .keyboardShortcut(.return, modifiers: .command)
                .hidden()
        }
        .onAppear {
            recents = loadRecents()
            fieldFocused = true
        }
        .task(id: query) { await debouncedSearch() }
        .task(id: scope)  { await runSearch() }
    }

    // MARK: - Rows

    private var inputRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.secondary)
            TextField("Search objects…", text: $query)
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($fieldFocused)
                .onSubmit { activate(.reveal) }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.escape) { dismiss(); return .handled }
        }
        .padding(14)
    }

    private var scopeRow: some View {
        HStack(spacing: 6) {
            Text("In:").font(.caption).foregroundStyle(.secondary)
            ForEach(SearchScope.allCases) { option in
                Button { scope = option } label: {
                    Text(option.label)
                        .font(.caption)
                        .fontWeight(scope == option ? .semibold : .regular)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .foregroundStyle(scope == option ? .white : .secondary)
                        .background(Capsule().fill(scope == option ? Color.accentColor : .clear))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("\(rows.count) \(query.isEmpty ? "recent" : "matches")")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.35))
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            List {
                if query.isEmpty && !recents.isEmpty {
                    Section("Recent") { resultRows }
                } else if !query.isEmpty {
                    Section("Matches") { resultRows }
                } else {
                    Text("Start typing to search · recent objects appear here")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .frame(height: 320)
            .onChange(of: highlighted) { _, idx in
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(idx, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private var resultRows: some View {
        if rows.isEmpty {
            Text(query.isEmpty ? "No recent objects." : "No objects match “\(query)”.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .listRowSeparator(.hidden)
        } else {
            ForEach(Array(rows.enumerated()), id: \.element.objectID) { idx, obj in
                SearchResultRow(object: obj, query: query, isHighlighted: idx == highlighted)
                    .id(idx)
                    .contentShape(.rect)
                    .onTapGesture {
                        highlighted = idx
                        activate(.reveal)
                    }
                    .listRowBackground(idx == highlighted ? Color.accentColor.opacity(0.16) : Color.clear)
            }
        }
    }

    private var footerRow: some View {
        HStack(spacing: 14) {
            KeyHint("↩", "open")
            KeyHint("⌘↩", "open in new window")
            Spacer()
            KeyHint("⎋", "close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Behaviour

    private enum Activation { case reveal, newWindow }

    private func activate(_ which: Activation) {
        guard rows.indices.contains(highlighted) else { return }
        let obj = rows[highlighted]
        DBBrowserRecents.record(tns: tns, DBPinnedKey(obj))
        dismiss()
        switch which {
        case .reveal:    onReveal(obj)
        case .newWindow: onOpenInNewWindow(obj)
        }
    }

    private func move(_ delta: Int) {
        guard !rows.isEmpty else { return }
        highlighted = max(0, min(rows.count - 1, highlighted + delta))
    }

    private func debouncedSearch() async {
        guard !query.isEmpty else {
            matches = []
            highlighted = 0
            return
        }
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        await runSearch()
    }

    private func runSearch() async {
        guard !query.isEmpty else { return }
        var preds: [NSPredicate] = [NSPredicate(format: "name_ CONTAINS[c] %@", query)]
        if let types = scope.typeRawValues {
            preds.append(NSPredicate(format: "type_ IN %@", types))
        }
        let request = DBCacheObject.fetchRequest(
            limit: 100,
            predicate: NSCompoundPredicate(type: .and, subpredicates: preds)
        )
        matches = (try? viewContext.fetch(request)) ?? []
        highlighted = 0
    }

    private func loadRecents() -> [DBCacheObject] {
        DBBrowserRecents.list(tns: tns).compactMap { key in
            let request = DBCacheObject.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(
                format: "owner_ = %@ AND name_ = %@ AND type_ = %@",
                key.owner, key.name, key.type
            )
            return (try? viewContext.fetch(request))?.first
        }
    }
}

// MARK: - Result row

private struct SearchResultRow: View {
    let object: DBCacheObject
    let query: String
    let isHighlighted: Bool

    private var type: OracleObjectType { OracleObjectType(rawValue: object.type) ?? .unknown }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: type.symbolName)
                .foregroundStyle(type.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 0) {
                    Text("\(object.owner).").foregroundStyle(.tertiary)
                    highlightedName
                }
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if !object.isValid {
                StatusPill(text: "INVALID", role: .invalid)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts = [type.label]
        if let ddl = object.lastDDLDate {
            parts.append("updated \(ddl.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }

    /// Object name with the matched substring emphasised.
    private var highlightedName: Text {
        let name = object.name
        guard !query.isEmpty,
              let range = name.range(of: query, options: [.caseInsensitive])
        else { return Text(name) }
        let pre = String(name[name.startIndex..<range.lowerBound])
        let mid = String(name[range])
        let post = String(name[range.upperBound...])
        return Text(pre)
            + Text(mid).foregroundStyle(.tint).fontWeight(.semibold)
            + Text(post)
    }
}

private struct KeyHint: View {
    let key: String
    let label: String
    init(_ key: String, _ label: String) { self.key = key; self.label = label }

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(.quaternary))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
