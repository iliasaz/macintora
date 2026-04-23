//
//  LogView.swift
//  MacOra
//
//  Created by Ilia on 3/15/22.
//

import SwiftUI
import OSLog

nonisolated(unsafe) let store = try? OSLogStore(scope: .currentProcessIdentifier)
nonisolated(unsafe) let oneMinuteAgo = store?.position(timeIntervalSinceEnd: -60)
nonisolated(unsafe) let predicate = NSPredicate(format: "category == %@", argumentArray: ["generic"])

func getEntries() -> String {
    var osLogEntries = try? store?.getEntries(with: [.reverse], at: oneMinuteAgo, matching: predicate)
    let s = osLogEntries?.map { "\($0.composedMessage) \n" }.joined() ?? ""
//    print(">>> \(s) <<<")
    return s
}

struct LogView: View {
    @State var entries = try? store?.getEntries(with: [], at: oneMinuteAgo, matching: nil)
    var body: some View {
        Text(getEntries())
            .multilineTextAlignment(.leading)
            .lineLimit(10)
    }
}

struct LogView_Previews: PreviewProvider {
    static var previews: some View {
        LogView()
    }
}
