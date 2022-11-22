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
        case editor, browser
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
        }
        .padding(20)
        .frame(width: 600, height: 200)
    }
}

struct EditorSettings: View {
    @AppStorage("tnsnamesPath") private var tnsnamesPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/instantclient_19_8/network/admin/tnsnames.ora"
    @AppStorage("formatterPath") private var formatterPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/Macintora/formatter"
    @AppStorage("shellPath") private var shellPath = "/bin/zsh"
    @AppStorage("rowFetchLimit") private var rowFetchLimit: Int = 200
    @AppStorage("queryPrefetchSize") private var queryPrefetchSize: Int = 200
    @AppStorage("serverTimeSeconds") private var serverTimeSeconds = false

    var body: some View {
        Form {
            TextField("TNS Path", text: $tnsnamesPath)
                .disableAutocorrection(true)
                .textFieldStyle(.roundedBorder)
            
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

        }
        .padding(20)
        .frame(width: 600, height: 200)
    }
}

struct DBBrowserSettings: View {
    @AppStorage("includeSystemObjects") private var includeSystemObjects = false
    @AppStorage("cacheUpdatePrefetchSize") private var cacheUpdatePrefetchSize: Int = 10000
    @AppStorage("cacheUpdateBatchSize") private var cacheUpdateBatchSize: Int = 200
    @AppStorage("cacheUpdateSessionLimit") private var cacheUpdateSessionLimit: Int = 5
    @AppStorage("searchLimit") private var searchLimit: Int = 20
    
    var body: some View {
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
        .padding(20)
        .frame(width: 600, height: 200)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
