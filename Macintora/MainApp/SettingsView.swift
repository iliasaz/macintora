//
//  Settings.swift
//  Macintora
//
//  Created by Ilia Sazonov on 8/26/22.
//

import SwiftUI

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
        }
        .padding(20)
        .frame(width: 600, height: 200)
    }
}

struct DBBrowserSettings: View {
    @AppStorage("includeSystemObjects") private var includeSystemObjects = false

    var body: some View {
        Form {
            Toggle("Include system objects", isOn: $includeSystemObjects)
                .disabled(true)
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
