//
//  ContentView.swift
//  WaitChains
//
//  Created by Ilia Sazonov on 7/21/23.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundColor(.accentColor)
            Text("Hello, world!")
            Button("GetData") {
                Task {
                    var c = SessionChainAnalyzer(dbid: 1116568641, beginSnap: 14255, endSnap: 14255)
                    try await c.getData()
                }
            }
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
