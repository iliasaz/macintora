//
//  SBMainView.swift
//  Macintora
//
//  Created by Ilia Sazonov on 9/16/22.
//

import SwiftUI

struct SBMainView: View {
    @ObservedObject private var vm: SBVM
    @State var theWindow: NSWindow?
    
    init(connDetails: SBConnDetails) {
        vm = SBVM(connDetails: connDetails)
    }
    
    var body: some View {
        VStack {
            ZStack {
                Text("Not connected")
                    .hidden(vm.connStatus == .connected || vm.connStatus == .changing)
                SessionView(model: vm)
                    .hidden(vm.connStatus == .disconnected || vm.connStatus == .changing)
                ProgressView(vm.isExecuting ? "Refreshing..." : "Connecting...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .hidden(vm.connStatus == .connected && !vm.isExecuting || vm.connStatus == .disconnected)
            }
        }
        .padding()
        .navigationTitle("Sessions @\(vm.connDetails.mainConnDetails.tns)")
        // a hack to get the current window handler
        .background {
            WindowAccessor(window: $theWindow)
        }
        .onAppear() {
            if vm.connStatus == .disconnected {
                vm.connectAndQuery()
            }
        }
        .onExitCommand {
            if vm.connStatus == .connected {
                vm.disconnect()
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


