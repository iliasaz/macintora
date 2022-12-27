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
    @ObservedObject private var vm: SBVM
    @State var theWindow: NSWindow?
    
    init(inputValue: SBInputValue) {
        vm = SBVM(mainConnection: inputValue.mainConnection)
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
                                Label("Refresh", systemImage: "arrow.triangle.2.circlepath").foregroundColor(.blue)
                            }
                                .keyboardShortcut("r", modifiers: .command)
                                .help("Refresh")
                            
                            Toggle(isOn: $vm.activeOnly) { Label("Active Only", systemImage: vm.activeOnly ? "externaldrive.fill.badge.wifi" : "externaldrive.badge.wifi") }
                                .toggleStyle(.automatic)
                                .foregroundColor(vm.activeOnly ? .green : nil)
                                .help("Active Only")
                            
                            Toggle(isOn: $vm.userOnly) { Label("User Only", systemImage: vm.userOnly ? "person.fill" : "person") }
                                .toggleStyle(.automatic)
                                .foregroundColor(vm.userOnly ? .green : nil)
                                .help("User Only")
                            
                            Toggle(isOn: $vm.localInstanceOnly) { Label("Local Instance Only", systemImage: "server.rack") }
                                .toggleStyle(.automatic)
                                .foregroundColor(vm.localInstanceOnly ? .green : nil)
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
            if vm.connStatus == .disconnected {
                vm.connectAndQuery()
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
            self.window = view.window   // << right after inserted in window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}


