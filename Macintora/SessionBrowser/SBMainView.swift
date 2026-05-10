//
//  SBMainView.swift
//  Macintora
//
//  Created by Ilia Sazonov on 9/16/22.
//

import SwiftUI

struct SBInputValue: Hashable, Codable {
    var mainConnection: MainConnection
    
    static func preview() -> SBInputValue { SBInputValue(mainConnection: MainConnection.preview()) }
}


struct SBMainView: View {
    @State private var vm: SBVM
    @State var theWindow: NSWindow?

    @Environment(\.connectionStore) private var injectedStore
    @Environment(\.keychainService) private var keychain

    init(inputValue: SBInputValue) {
        _vm = State(wrappedValue: SBVM(mainConnection: inputValue.mainConnection))
    }
    
    var body: some View {
        VStack {
            ZStack {
                Text("Not connected")
                    .hidden(vm.connStatus == .connected || vm.connStatus == .changing)
                SessionView(model: vm)
                    .toolbar {
                        ToolbarItemGroup(placement: .principal) {
                            Button {
                                vm.populateData()
                            } label: {
                                Label("Refresh", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.blue)
                            }
                                .keyboardShortcut("r", modifiers: .command)
                                .help("Refresh")
                            
                            Toggle(isOn: $vm.activeOnly) { Label("Active Only", systemImage: vm.activeOnly ? "externaldrive.fill.badge.wifi" : "externaldrive.badge.wifi") }
                                .toggleStyle(.automatic)
                                .foregroundStyle(vm.activeOnly ? AnyShapeStyle(Color.green) : AnyShapeStyle(.primary))
                                .help("Active Only")
                            
                            Toggle(isOn: $vm.userOnly) { Label("User Only", systemImage: vm.userOnly ? "person.fill" : "person") }
                                .toggleStyle(.automatic)
                                .foregroundStyle(vm.userOnly ? AnyShapeStyle(Color.green) : AnyShapeStyle(.primary))
                                .help("User Only")
                            
                            Toggle(isOn: $vm.localInstanceOnly) { Label("Local Instance Only", systemImage: "server.rack") }
                                .toggleStyle(.automatic)
                                .foregroundStyle(vm.localInstanceOnly ? AnyShapeStyle(Color.green) : AnyShapeStyle(.primary))
                                .help("Local Instance Only")
                        }
                    }
                    .buttonStyle(.borderedProminent)
//                    .labelStyle(.titleAndIcon)
                    .hidden(vm.connStatus == .disconnected || vm.connStatus == .changing)
                
                ProgressView(vm.isExecuting ? "Refreshing..." : "Connecting...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .hidden(vm.connStatus == .connected && !vm.isExecuting || vm.connStatus == .disconnected)
            }
        }
        .padding()
        .navigationTitle("Sessions @\(vm.mainConnection.mainConnDetails.tns)")
        // a hack to get the current window handler
        .background {
            WindowAccessor(window: $theWindow)
        }
        .onAppear() {
            guard let injectedStore else { return }
            if vm.connStatus == .disconnected {
                vm.connectAndQuery(store: injectedStore, keychain: keychain)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: theWindow)) { _ in
            if vm.connStatus == .connected {
                vm.disconnect()
            }
        }
    }
}



// a hack to get the current window handler
struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = unsafe view.window   // << right after inserted in window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}


