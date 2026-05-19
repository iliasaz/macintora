//
//  DBDetailView.swift
//  Macintora
//
//  Created by Ilia Sazonov on 8/31/22.
//
//  Layout:
//   ┌──────────────────────────────────────────────────────────┐
//   │  icon + qualified name      [Edit Source][↻][Inspector ⌘I]│  ← header strip
//   ├──────────────────────────────────────────────────────────┤
//   │  ┌──────────────────────────┐  Tabs:                      │
//   │  │ Content                  │   Columns · Indexes ·       │
//   │  │ (gets the room)          │   Triggers · SQL            │
//   │  └──────────────────────────┘                             │
//   └──────────────────────────────────────────────────────────┘
//                                              + right Inspector
//   The inspector is the single home for object-level metadata
//   (replacing the older collapsible "Object details" accordion).
//   When a row is selected inside a sub-tab (Columns, Indexes,
//   Triggers), the inspector swaps to that child's detail.
//

import SwiftUI
import os
import AppKit

/// `Tab` retained as a type for back-compat with persisted `DBCacheInputValue`
/// payloads but the dual Main/Details tab split is gone.
enum DBDetailTab: String, Codable, Hashable, CaseIterable, Sendable {
    case main
    case details
}

/// Unified child-row selection for table sub-tabs. The inspector dispatches on
/// this to show a row-specific detail; when `nil` it shows object-level info
/// for the current `dbObject`.
enum DBChildSelection {
    case column(DBCacheTableColumn)
    case index(DBCacheIndex)
    case trigger(DBCacheTrigger)
}

struct DBDetailView: View {
    @Binding var dbObject: DBCacheObject
    @EnvironmentObject private var cache: DBCacheVM
    @AppStorage("dbDetailInspectorOpen") private var inspectorOpen = true
    @State private var childSelection: DBChildSelection?

    var body: some View {
        // Inline right-rail composition. We're not using `.inspector` here
        // because `DBCacheMainView` already owns the outer NavigationSplitView's
        // inspector slot for the quick-filter panel — stacking two doesn't
        // work cleanly in macOS SwiftUI.
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                DBDetailViewHeader(
                    dbObject: $dbObject,
                    inspectorOpen: $inspectorOpen
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                Divider()

                DBDetailContent(dbObject: $dbObject, childSelection: $childSelection)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if inspectorOpen {
                Divider()
                DBDetailInspectorView(dbObject: $dbObject, childSelection: $childSelection)
                    .frame(width: 280)
                    .background(SidebarVisualEffect())
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: inspectorOpen)
        .onChange(of: dbObject.objectId) { childSelection = nil }
    }
}

// MARK: - Header strip

struct DBDetailViewHeader: View {
    @Binding var dbObject: DBCacheObject
    @Binding var inspectorOpen: Bool
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

            Button {
                inspectorOpen.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sidebar.right")
                    Text("Inspector")
                    KeyBadge(label: "\u{2318}I")
                }
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("i", modifiers: [.command])
            .help("Toggle Inspector (\u{2318}I)")
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

/// Compact monospaced key-shortcut badge (e.g. "⌘I"). Renders the same chip
/// styling that used to live next to the dropped "Object details" accordion.
struct KeyBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.12)))
            .foregroundStyle(.tertiary)
    }
}

/// `.sidebar` material backed by NSVisualEffectView so the inspector matches
/// the translucent vibrancy of the navigation sidebar instead of the flat
/// `.regularMaterial` panel look. `Material.bar` is the closest SwiftUI-native
/// option but reads as a toolbar; the sidebar material is what we actually
/// want here.
struct SidebarVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .sidebar
        v.blendingMode = .behindWindow
        v.state = .followsWindowActiveState
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Content router

/// Routes to the right detail body for the selected object's type.
struct DBDetailContent: View {
    @Binding var dbObject: DBCacheObject
    @Binding var childSelection: DBChildSelection?

    var body: some View {
        switch OracleObjectType(rawValue: dbObject.type) ?? .unknown {
        case .table, .view:
            DBTableDetailView(dbObject: $dbObject, childSelection: $childSelection)
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
