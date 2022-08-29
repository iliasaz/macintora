//
//  LoginView.swift
//  MacOra
//
//  Created by Ilia on 3/12/22.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var tnsReader: TnsReader
    @EnvironmentObject var document: MainDocumentVM
    @Environment(\.undoManager) var undoManager
    @State private var username: String = ""
    @State private var password: String = ""
//    @FocusState private var focusedView: FocusedView?
    @FocusState private var isUsernameFocused: Bool
    @FocusState private var isPasswordFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading) {
//            TextField("username", text: Binding(get: {document.connDetails.username}, set: {
//                newValue in document.connDetails.username = newValue
//                undoManager?.registerUndo(withTarget: document, handler: {print($0, "undo")})
//            }))
            TextField("username", text: $username)
                .focused($isUsernameFocused)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 50)
                .disableAutocorrection(true)
                .onChange(of: isUsernameFocused) { isFocused in
                    log.debug("username focus: \(isFocused)")
                    if !isFocused { document.connDetails.username = username }
                }
                .disabled(document.isConnected == .connected)
            
            SecureField("password", text: $password)
                .focused($isPasswordFocused)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 50)
                .disableAutocorrection(true)
                .onChange(of: isPasswordFocused) { isFocused in
                    log.debug("password focus: \(isFocused)")
                    if !isFocused { document.connDetails.password = password }
                }
                .disabled(document.isConnected == .connected)
            
            TextField("some", text: Binding(get: { document.connDetails.tns ?? ""}, set: {_,_ in }))
                .disabled(true)

            Picker(selection: $document.connDetails.connectionRole, label: Text("Connect As:")) {
                Text("Regular").tag(ConnectionRole.regular)
                Text("SysDBA").tag(ConnectionRole.sysDBA)
//                Text("SysOper").tag(ConnectionRole.sysOper)
            }.pickerStyle(RadioGroupPickerStyle())
            
            HStack {
                // connect/disconnect
                Button {
                    if document.isConnected == .connected {
                        document.disconnect()
                    } else if document.isConnected == .disconnected {
                        document.connect()
                    } else {
                        // connecting or disconnecting
                    }
                } label: {
                    if document.isConnected == .connected {
                        Text("Disconnect")
                    } else if document.isConnected == .disconnected{
                        Text("Connect")
                    } else {
                        Image(systemName: "lightbulb.fill").foregroundColor(Color.orange)
                    }
                }
            }
            .disabled(document.isConnected == .changing)
            Spacer()
        }
        .onAppear() {
            username = document.connDetails.username
            password = document.connDetails.password
        }
    }
}

//struct LoginView_Previews: PreviewProvider {
//    static var tns = "test"
//    static var previews: some View {
//        LoginView(tns: tns)
//            .environmentObject(MainDocumentVM())
//    }
//}
