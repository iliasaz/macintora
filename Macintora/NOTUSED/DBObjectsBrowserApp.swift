////
////  DBObjectsBrowserApp.swift
////  DBObjectsBrowser
////
////  Created by Ilia on 1/1/22.
////
//
//import SwiftUI
//import ArgumentParser
//
//import os
//
//fileprivate let log = Logger(subsystem: "com.iliasazonov.macintora", category: "DBObjectsBrowser")
//
////var connDetails = ConnectionDetails(username: "apps", password: "apps", tns: "dmwoac", connectionRole: .regular)
//
//
//struct CommandLineArguments: ParsableArguments {
//    @Argument(help: "username/password@db")
//    var connstring: String?
//
//    func getConnDetails() -> ConnectionDetails {
//        guard let connString = connstring  else { fatalError() }
//        let username = String(connString.split(separator: "/")[0])
//        let password = String(connString.split(separator: "/")[1].split(separator: "@")[0])
//        let tns = String(connString.split(separator: "/")[1].split(separator: "@")[1])
//        let conn = ConnectionDetails(username: username, password: password, tns: tns, connectionRole: .regular)
//        return conn
//    }
//}
//
//@main
//struct DBObjectsBrowserApp: App {
//    var connDetails: ConnectionDetails = {
//        var conn: ConnectionDetails
//        do {
//
//            let args = try CommandLineArguments.parse()
//            conn = args.getConnDetails()
//        } catch {
//            let message = CommandLineArguments.message(for: error)
//            log.error("Could not parse input arguments: \(error.localizedDescription), \(message)")
//            conn = ConnectionDetails(tns: "dmwoac")
//        }
//        return conn
//    }()
//
//    var body: some Scene {
//        WindowGroup {
//            DBCacheBrowserMainView(cache: DBCacheVM(connDetails: connDetails))
//        }
//        .commands {
//            SidebarCommands()
//            ToolbarCommands()
//            TextEditingCommands()
//            CommandGroup(after: .newItem) {
//                Button(action: {
//                    if let currentWindow = NSApp.keyWindow,
//                       let windowController = currentWindow.windowController {
//                        windowController.newWindowForTab(nil)
//                        if let newWindow = NSApp.keyWindow,
//                           currentWindow != newWindow {
//                            currentWindow.addTabbedWindow(newWindow, ordered: .above)
//                        }
//                    }
//                }) {
//                    Text("New Tab")
//                }
//                .keyboardShortcut("t", modifiers: [.command])
//            }
//        }
//    }
//}
