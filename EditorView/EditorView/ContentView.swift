//
//  ContentView.swift
//  EditorView
//
//  Created by Ilia Sazonov on 7/13/23.
//

import SwiftUI

struct ContentView: View {
    @State private var text: AttributedString = ""
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundColor(.accentColor)
            Text("Hello, world!")
            TextView(text: $text, options: [.wrapLines, .highlightSelectedLine])
                .textViewFont(.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular))
        }
        .padding()
        .onAppear {
            loadContent()
        }
    }

    private func loadContent() {
        let string = try! String(contentsOf: Bundle.main.url(forResource: "content", withExtension: "txt")!)
        self.text = AttributedString(string)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
