//
//  DBDetailView.swift
//  Macintora
//
//  Created by Ilia Sazonov on 8/31/22.
//
//  v2 layout (design B picks consolidated):
//   ┌──────────────────────────────────────────────────────────┐
//   │  icon + qualified name              [Edit Source][↻][⌘I] │  ← header strip
//   ├──────────────────────────────────────────────────────────┤
//   │  ▶  Object details · Owner / ID / Last DDL · ● Valid      │  ← collapsed accordion
//   ├──────────────────────────────────────────────────────────┤
//   │  ┌──────────────────────────┐  Tabs:                      │
//   │  │ Columns content         │   Columns · Indexes ·        │  ← top-level tabs
//   │  │ (gets the room)         │   Triggers · SQL             │
//   │  └──────────────────────────┘                              │
//   └──────────────────────────────────────────────────────────┘
//                                              + right Inspector

import SwiftUI
import os

/// `Tab` retained as a type for back-compat with persisted `DBCacheInputValue`
/// payloads but the dual Main/Details tab split is gone.
enum DBDetailTab: String, Codable, Hashable, CaseIterable, Sendable {
    case main
    case details
}

struct DBDetailView: View {
    @Binding var dbObject: DBCacheObject
    @EnvironmentObject private var cache: DBCacheVM
    @AppStorage("dbDetailAccordionOpen") private var accordionOpen = false
    @AppStorage("dbDetailInspectorOpen") private var inspectorOpen = true

    var body: some View {
        // Inline right-rail composition. We're not using `.inspector` here
        // because `DBCacheMainView` already owns the outer NavigationSplitView's
        // inspector slot for the quick-filter panel — stacking two doesn't
        // work cleanly in macOS SwiftUI.
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                DBDetailViewHeader(
                    dbObject: $dbObject,
                    inspectorOpen: $inspectorOpen,
                    accordionOpen: $accordionOpen
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                Divider()

                DBDetailAccordion(dbObject: $dbObject, isOpen: $accordionOpen)

                DBDetailContent(dbObject: $dbObject)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if inspectorOpen {
                Divider()
                DBDetailInspectorView(dbObject: $dbObject)
                    .frame(width: 280)
                    .background(.regularMaterial)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: inspectorOpen)
    }
}

// MARK: - Header strip

struct DBDetailViewHeader: View {
    @Binding var dbObject: DBCacheObject
    @Binding var inspectorOpen: Bool
    @Binding var accordionOpen: Bool
    @State private var isRefreshing = false
    @State private var isLoadingSource = false
    @EnvironmentObject private var cache: DBCacheVM

    private var type: OracleObjectType {
        OracleObjectType(rawValue: dbObject.type) ?? .unknown
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: type.symbolName)
                .font(.title3)
                .foregroundStyle(type.tint)
                .frame(width: 22)

            Text(type.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(dbObject.name)
                .font(.title3)
                .bold()
                .textSelection(.enabled)

            Text("(\(dbObject.owner))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Spacer()

            Button("Edit Source", systemImage: "square.and.pencil") {
                guard !isLoadingSource else { return }
                Task(priority: .background) {
                    isLoadingSource = true
                    if let url = await cache.editSource(dbObject: dbObject) {
                        NSWorkspace.shared.open(url)
                    }
                    isLoadingSource = false
                }
            }
            .buttonStyle(.borderless)
            .disabled(isLoadingSource)
            .help("Open source in editor")

            if isLoadingSource {
                ProgressView().controlSize(.small)
            }

            Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
                .help("Refresh this object")

            if isRefreshing {
                ProgressView().controlSize(.small)
            }

            Button("Inspector", systemImage: "sidebar.right") {
                inspectorOpen.toggle()
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("i", modifiers: [.option, .command])
            .help("Toggle Inspector (⌥⌘I)")
        }
    }

    private func refresh() {
        Task(priority: .background) {
            await MainActor.run { isRefreshing = true }
            do {
                try await cache.connectSvc()
                await MainActor.run { cache.isConnected = .connected }
            } catch {
                log.cache.error("not connected")
                await MainActor.run { isRefreshing = false }
                return
            }
            await cache.refreshObject(OracleObject(
                owner: dbObject.owner,
                name: dbObject.name,
                type: OracleObjectType(rawValue: dbObject.type) ?? .unknown,
                lastDDL: dbObject.lastDDLDate ?? Constants.minDate,
                createDate: dbObject.createDate ?? Constants.minDate,
                editionName: dbObject.editionName,
                isEditionable: dbObject.isEditionable,
                isValid: dbObject.isValid,
                objectId: dbObject.objectId
            ))
            await cache.disconnectSvc()
            await MainActor.run { isRefreshing = false }
        }
    }
}

// MARK: - Accordion ("Object details")

/// Collapsed: one-line summary strip. Expanded: 4-column grid of metadata.
/// Default state is collapsed because Columns/Source typically deserves the
/// space; users open the accordion when they specifically want metadata.
struct DBDetailAccordion: View {
    @Binding var dbObject: DBCacheObject
    @Binding var isOpen: Bool

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Text("Object details")
                        .font(.callout)
                        .bold()
                    if !isOpen {
                        AccordionSummary(dbObject: dbObject)
                            .padding(.leading, 6)
                    }
                    Spacer(minLength: 0)
                    Text("⌘I")
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.12)))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("i", modifiers: [.command])
            .background(Color.secondary.opacity(0.06))

            if isOpen {
                AccordionExpanded(dbObject: dbObject)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()
        }
    }
}

private struct AccordionSummary: View {
    let dbObject: DBCacheObject

    var body: some View {
        HStack(spacing: 14) {
            SummaryItem(label: "Owner", value: dbObject.owner)
            SummaryItem(label: "ID", value: dbObject.objectId.formatted(.number.grouping(.never)))
            if let ddl = dbObject.lastDDLDate {
                SummaryItem(label: "Last DDL", value: ddl.formatted(date: .abbreviated, time: .omitted))
            }
            HStack(spacing: 4) {
                Circle()
                    .fill(dbObject.isValid ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(dbObject.isValid ? "Valid" : "Invalid")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }
}

private struct SummaryItem: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.tertiary)
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AccordionExpanded: View {
    let dbObject: DBCacheObject

    private let columns = [GridItem(.flexible(), alignment: .topLeading),
                           GridItem(.flexible(), alignment: .topLeading),
                           GridItem(.flexible(), alignment: .topLeading),
                           GridItem(.flexible(), alignment: .topLeading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            Field(label: "Owner", value: dbObject.owner)
            Field(label: "Object ID", value: dbObject.objectId.formatted(.number.grouping(.never)))
            Field(label: "Created",
                  value: dbObject.createDate?
                    .formatted(date: .abbreviated, time: .shortened) ?? Constants.nullValue)
            Field(label: "Last DDL",
                  value: dbObject.lastDDLDate?
                    .formatted(date: .abbreviated, time: .shortened) ?? Constants.nullValue)
            Field(label: "Edition", value: dbObject.editionName ?? Constants.nullValue)
            Field(label: "Editionable", value: dbObject.isEditionable ? "Yes" : "No")
            Field(label: "Valid") {
                BoolIndicator(value: dbObject.isValid, trueColor: .green, falseColor: .red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.04))
    }
}

private struct Field<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    init(label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .kerning(0.4)
            content()
                .font(.callout)
        }
    }
}

private extension Field where Content == Text {
    init(label: String, value: String) {
        self.init(label: label) { Text(value) }
    }
}

// MARK: - Content router

/// Routes to the right detail body for the selected object's type. Drops the
/// old `Main` (form-style overview) tab — its content now lives in the
/// accordion + inspector.
struct DBDetailContent: View {
    @Binding var dbObject: DBCacheObject

    var body: some View {
        switch OracleObjectType(rawValue: dbObject.type) ?? .unknown {
        case .table, .view:
            DBTableDetailView(dbObject: $dbObject)
        case .type, .package, .procedure, .function:
            CodeDetailContent(dbObject: $dbObject)
        case .trigger:
            DBTriggerDetailView(dbObject: $dbObject)
        case .index:
            DBIndexDetailView(dbObject: $dbObject)
        case .unknown:
            ContentUnavailableView("Unknown object type", systemImage: "questionmark.square")
        }
    }
}

/// Code-object wrapper: the source viewer (with its own spec/body tabs and a
/// navigable symbol outline rail). The old DB-sourced member list that used to
/// dock below has been replaced by `CodeOutlineView` inside `SourceView`.
struct CodeDetailContent: View {
    @Binding var dbObject: DBCacheObject

    var body: some View {
        DBSourceDetailView(dbObject: $dbObject)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Header image (back-compat)

struct DBDetailViewHeaderImage: View {
    @Binding var type: OracleObjectType

    var body: some View {
        Label(type.label, systemImage: type.symbolName)
            .foregroundStyle(type.tint)
    }
}

/// Non-interactive boolean presenter for read-only fields. Replaces
/// `Toggle(isOn: .constant(...))`, which renders an interactive-looking
/// switch that doesn't actually toggle.
struct BoolIndicator: View {
    let value: Bool
    var trueColor: Color = .accentColor
    var falseColor: Color = .secondary

    var body: some View {
        Image(systemName: value ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(value ? trueColor : falseColor)
            .accessibilityLabel(value ? "Yes" : "No")
    }
}

struct DBDetailView_Previews: PreviewProvider {
    static var previews: some View {
        DBDetailView(dbObject: .constant(DBCacheObject.exampleTrigger))
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
            .frame(width: 1000, height: 800)
        DBDetailView(dbObject: .constant(DBCacheObject.exampleTable))
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
            .frame(width: 1000, height: 800)
        DBDetailView(dbObject: .constant(DBCacheObject.examplePackage))
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
            .frame(width: 1000, height: 800)
    }
}
