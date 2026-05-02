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
        case editor, browser, connections
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
            ConnectionsManagerView()
                .tabItem {
                    Label("Connections", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .tag(Tabs.connections)
        }
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
    @AppStorage(QuickViewHotkey.storageKey) private var quickViewHotkeyRaw: String = QuickViewHotkey.default.rawValue

    private var quickViewHotkeyBinding: Binding<QuickViewHotkey> {
        Binding(
            get: { QuickViewHotkey(rawValue: quickViewHotkeyRaw) ?? .default },
            set: { quickViewHotkeyRaw = $0.rawValue }
        )
    }

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

                Picker("Quick View Hotkey", selection: quickViewHotkeyBinding) {
                    ForEach(QuickViewHotkey.allCases) { hotkey in
                        Text(hotkey.displayName).tag(hotkey)
                    }
                }
                .help("Shortcut to open the DB Object Quick View popover at the cursor.")

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
    @AppStorage("searchLimit") private var searchLimit: Int = 20

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

                TextField("Search Limit", value: $searchLimit, format: .number)
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
