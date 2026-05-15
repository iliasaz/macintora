//
//  Settings.swift
//  Macintora
//
//  Created by Ilia Sazonov on 8/26/22.
//

import SwiftUI
import AppKit

struct SettingsView: View {
    private enum Tabs: Hashable {
        case editor, browser, appearance, connections
    }
    var body: some View {
        TabView {
            EditorSettings()
                .tabItem {
                    Label("Editor", systemImage: "gear")
                }
                .tag(Tabs.editor)
            DBBrowserSettings()
                .tabItem {
                    Label("DB Browser", systemImage: "server.rack")
                }
                .tag(Tabs.browser)
                .padding(10)
            AppearanceSettings()
                .tabItem {
                    Label("Appearance", systemImage: "paintpalette")
                }
                .tag(Tabs.appearance)
            ConnectionsManagerView()
                .tabItem {
                    Label("Connections", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .tag(Tabs.connections)
        }
    }
}

/// User-selectable app accent. `.system` opts out of overriding the macOS
/// accent (no `.tint` applied at the scene root); the named cases override
/// it with a fixed swatch matching the standard AppKit accent presets.
enum AppAccentColor: String, CaseIterable, Identifiable {
    case system
    case blue
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case graphite

    static let storageKey = "appAccentColor"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "Match System"
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .graphite: "Graphite"
        }
    }

    /// `nil` means "don't override the system accent" — caller should skip
    /// applying `.tint(...)` so views fall back to `NSColor.controlAccentColor`.
    var color: Color? {
        switch self {
        case .system: nil
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .graphite: Color(nsColor: .systemGray)
        }
    }
}

struct AppearanceSettings: View {
    @AppStorage(AppAccentColor.storageKey) private var accentRaw: String = AppAccentColor.system.rawValue

    private var accentBinding: Binding<AppAccentColor> {
        Binding(
            get: { AppAccentColor(rawValue: accentRaw) ?? .system },
            set: { accentRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack {
            Form {
                Picker("Accent Color", selection: accentBinding) {
                    ForEach(AppAccentColor.allCases) { accent in
                        HStack {
                            if let color = accent.color {
                                Circle()
                                    .fill(color)
                                    .frame(width: 12, height: 12)
                            } else {
                                Circle()
                                    .strokeBorder(Color.secondary, lineWidth: 1)
                                    .frame(width: 12, height: 12)
                            }
                            Text(accent.displayName)
                        }
                        .tag(accent)
                    }
                }
                .help("Overrides the macOS system accent within Macintora. Match System defers to your System Settings choice.")
            }
            Spacer()
        }
        .padding(20)
    }
}

/// Reads the persisted `AppAccentColor` and applies `.tint(...)` when the
/// user picked an explicit override. `.system` leaves the tint alone so
/// SwiftUI falls back to `NSColor.controlAccentColor`.
struct AppAccentTintModifier: ViewModifier {
    @AppStorage(AppAccentColor.storageKey) private var accentRaw: String = AppAccentColor.system.rawValue

    private var accent: AppAccentColor {
        AppAccentColor(rawValue: accentRaw) ?? .system
    }

    func body(content: Content) -> some View {
        if let color = accent.color {
            content.tint(color)
        } else {
            content
        }
    }
}

extension View {
    func macintoraAccentTint() -> some View {
        modifier(AppAccentTintModifier())
    }
}

/// Storage keys for the Script Runner-related settings. Centralised so both
/// `EditorSettings` (the SwiftUI form) and `ResultsController` (the
/// consumer) reference the same `@AppStorage` keys.
enum ScriptRunnerDefaults {
    static let dbmsOutputInline = "scriptRunner.dbmsOutputInline"
    static let miniGridRowCap = "scriptRunner.miniGridRowCap"
    static let alwaysStopOnError = "scriptRunner.alwaysStopOnError"
}

struct EditorSettings: View {
    @AppStorage("formatterPath") private var formatterPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/Macintora/formatter"
    @AppStorage("shellPath") private var shellPath = "/bin/zsh"
    @AppStorage("rowFetchLimit") private var rowFetchLimit: Int = 200
    @AppStorage("queryPrefetchSize") private var queryPrefetchSize: Int = 200
    @AppStorage("serverTimeSeconds") private var serverTimeSeconds = false
    @AppStorage("wordWrap") private var wordWrap = false
    @AppStorage("editorTheme") private var editorThemeRaw: String = EditorTheme.default.rawValue
    @AppStorage(TimestampDisplayMode.storageKey) private var timestampDisplayModeRaw: String = TimestampDisplayMode.mixed.rawValue
    @AppStorage(ScriptRunnerDefaults.dbmsOutputInline) private var scriptDbmsOutputInline: Bool = true
    @AppStorage(ScriptRunnerDefaults.miniGridRowCap) private var scriptMiniGridRowCap: Int = 200
    @AppStorage(ScriptRunnerDefaults.alwaysStopOnError) private var scriptAlwaysStopOnError: Bool = false

    private var editorThemeBinding: Binding<EditorTheme> {
        Binding(
            get: { EditorTheme(rawValue: editorThemeRaw) ?? .default },
            set: { editorThemeRaw = $0.rawValue }
        )
    }

    private var timestampDisplayModeBinding: Binding<TimestampDisplayMode> {
        Binding(
            get: { TimestampDisplayMode(rawValue: timestampDisplayModeRaw) ?? .mixed },
            set: { timestampDisplayModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack {
            Form {
                TextField("Formatter Path", text: $formatterPath)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)

                TextField("Shell Command", text: $shellPath)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)

                TextField("Row Fetch Limit", value: $rowFetchLimit, format: .number)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)

                TextField("Query PreFetch Size", value: $queryPrefetchSize, format: .number)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)

                Toggle("Show seconds in server time", isOn: $serverTimeSeconds)

                Toggle("Word Wrapping", isOn: $wordWrap)

                Picker("Color Theme", selection: editorThemeBinding) {
                    ForEach(EditorTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }

                Picker("Timestamp Display", selection: timestampDisplayModeBinding) {
                    ForEach(TimestampDisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Section("Script Runner") {
                    Toggle("Show DBMS_OUTPUT inline", isOn: $scriptDbmsOutputInline)
                        .help("Default value of SET SERVEROUTPUT for new scripts.")
                    Stepper(value: $scriptMiniGridRowCap, in: 50...2000, step: 50) {
                        Text("Mini-grid row cap: \(scriptMiniGridRowCap)")
                    }
                    .help("Max rows captured for inline SELECT preview. Promote to grid for more.")
                    Toggle("Stop on first error (override WHENEVER)", isOn: $scriptAlwaysStopOnError)
                        .help("When on, any failed unit halts the script regardless of WHENEVER SQLERROR.")
                }
            }
            Spacer()
        }
        .padding(20)
    }
}

struct DBBrowserSettings: View {
    @AppStorage("includeSystemObjects") private var includeSystemObjects = false
    @AppStorage("cacheUpdatePrefetchSize") private var cacheUpdatePrefetchSize: Int = 10000
    @AppStorage("cacheUpdateBatchSize") private var cacheUpdateBatchSize: Int = 200
    @AppStorage("cacheUpdateSessionLimit") private var cacheUpdateSessionLimit: Int = 5

    var body: some View {
        VStack {
            Form {
                TextField("Cache Update Prefetch Size", value: $cacheUpdatePrefetchSize, format: .number)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)

                TextField("Cache Update Batch Size", value: $cacheUpdateBatchSize, format: .number)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)

                TextField("Cache Update Max Sessions", value: $cacheUpdateSessionLimit, format: .number)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)

                Toggle("Include system objects", isOn: $includeSystemObjects)

            }
            Spacer()
        }
        .padding(20)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
