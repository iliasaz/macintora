//
//  ConnectionListView.swift
//  MacOra
//
//  Created by Ilia on 3/14/22.
//

import SwiftUI
import AppKit

struct ConnectionListView: View {
    @StateObject var tnsReader = TnsReader()
    @Binding var connectionSatus: ConnectionStatus
    @Binding var username: String
    @Binding var password: String
    @Binding var selectedTns: String
    @Binding var connectionRole: ConnectionRole
    var connect: (() -> Void)
    var disconnect: (() -> Void)
    @Environment(\.undoManager) var undoManager
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Connection").font(.title)
            HStack {
                Picker("", selection: $selectedTns) {
                    ForEach(tnsReader.tnsAliases, id: \.self) {alias in
                        Text(alias)
                    }
                }
                .labelsHidden()
                
                Button {
                    tnsReader.load()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath").foregroundColor(.blue)
                }
            }
            .frame(minWidth: 200, alignment: .leading)
            .disabled(connectionSatus == .connected)
            
            TextField("username", text: $username)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 50)
                .disableAutocorrection(true)
                .disabled(connectionSatus == .connected)
            
            SecureField("password", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 50)
                .disableAutocorrection(true)
                .disabled(connectionSatus == .connected)
            
            Picker(selection: $connectionRole, label: Text("Connect As:")) {
                Text("Regular").tag(ConnectionRole.regular)
                Text("SysDBA").tag(ConnectionRole.sysDBA)
            }
                .pickerStyle(SegmentedPickerStyle())
                .labelsHidden()
                .frame(width: 150)
                .disabled(connectionSatus == .connected)
            
            Button {
                if connectionSatus == .connected {
                    disconnect()
                } else {
                    connect()
                }
            } label: {
                if connectionSatus == .connected {
                    Text("Disconnect")
                } else {
                    Text("Connect")
                }
            }
            
            Spacer()
        }
        .padding()
    }
}

struct ConnectionListInnerView: View {
    @Binding var tnsAliases: [String]
    @State private var selectedTns: String = ""
    
    var body: some View {
        Picker("TNS", selection: $selectedTns) {
            ForEach(tnsAliases, id: \.self) {alias in
                Text(alias)
            }
        }
    }
}



struct ConnectionListView_Previews: PreviewProvider {
    static var previews: some View {
        ConnectionListView(
            connectionSatus: .constant(.disconnected),
            username: .constant("user"),
            password: .constant("password"),
            selectedTns: .constant("tns"),
            connectionRole: .constant(.regular),
            connect: {},
            disconnect: {}
        )
            .environmentObject(MainDocumentVM())
    }
}


// NOTUSED

//struct ConnectionListView_OLD: View {
//    @StateObject var tnsReader = TnsReader()
//    var body: some View {
//        VStack(alignment: .leading) {
//            Text("Connection").font(.title)
//            ConnectionListInnerView(tnsAliases: $tnsReader.tnsAliases)
//                .frame(minWidth: 200, maxHeight: 300, alignment: .topLeading)
//
//            Button {
//                tnsReader.load()
//            } label: {
//                Text("Reload tnsnames.ora")
//            }
//
//            Divider()
//            LoginView()
//
////            Spacer()
//        }
//        .padding()
//    }
//}
//
//struct ConnectionListInnerView_OLD: View {
//    @State var searchText: String = ""
//    @EnvironmentObject var document: MainDocumentVM
//    @StateObject var tnsReader = TnsReader()
////    @Binding @FocusState var focusedView: FocusedView?
//
//    var body: some View {
//        List(selection: $document.connDetails.tns) {
//            ForEach(searchResults, id: \.self) { alias in
//                Text(alias)
//                    .frame(minWidth: 200, alignment: .leading)
//            }
//        }
//        .searchable(text: $searchText, placement: .sidebar, prompt: "TNS alias")
//        .listStyle(SidebarListStyle())
//    }
//
//    var searchResults: [String] {
//        if searchText.isEmpty {
//            return tnsReader.tnsAliases
//        } else {
//            let list = tnsReader.tnsAliases.filter { $0.contains(searchText) }
////            if list.count == 1 { focusedView = .login }
//            return list
//        }
//    }
//}

//    func reloadConnections() {
//        let tnsReader = TnsReader()
//        if let data = UserDefaults.standard.data(forKey: "Connections") {
//            if let decoded = try? JSONDecoder().decode([ConnectionDetails].self, from: data) {
//                connections = decoded
//                // merge unused TNS entries with saved connections
//                let unusedTns = tnsReader.tnsAliases.subtracting( Set<String>(connections.map { $0.tns }.unique()) )
//                objectWillChange.send()
//                unusedTns.forEach { connections.append(ConnectionDetails(tns: $0)) }
//                connections.sort(by: <)
//                return
//            }
//        }
//        // if no saved conneections, load tns aliases
//        connections = tnsReader.tnsAliases.map { ConnectionDetails(tns: $0) }.sorted(by: <)
//    }
    
//    func saveConnection() {
//        objectWillChange.send()
//        let username = selectedConnDetails?.username ?? ""
//        let password = selectedConnDetails?.password ?? ""
//        let tns = selectedConnDetails?.tns ?? ""
//        let role = selectedConnDetails?.connectionRole
//        if let connIndex = connections.firstIndex(where: {$0.tns == tns && $0.username == username} ) {
//            connections[connIndex] = ConnectionDetails(username: username, password: password, tns: tns, connectionRole: role)
//        } else {
//            connections.append(ConnectionDetails(username: username, password: password, tns: tns, connectionRole: role))
//        }
//        connections.sort(by: <)
//        if let encoded = try? JSONEncoder().encode(connections) {
//            UserDefaults.standard.set(encoded, forKey: "Connections")
//        }
//    }
