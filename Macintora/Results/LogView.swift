import SwiftUI
import OSLog

/// Displays the most recent OSLog entries for the "generic" category.
///
/// The OSLogStore/OSLogPosition/NSPredicate values aren't `Sendable`, so we
/// keep them as `@MainActor` statics on the view rather than module-level
/// globals. Since the view only ever renders on the main actor, this avoids
/// the need for `nonisolated(unsafe)` and keeps the concurrency story clean.
struct LogView: View {
    @MainActor private static let store = try? OSLogStore(scope: .currentProcessIdentifier)
    @MainActor private static let oneMinuteAgo = store?.position(timeIntervalSinceEnd: -60)
    @MainActor private static let predicate = NSPredicate(format: "category == %@", argumentArray: ["generic"])

    @State private var entries: String = ""

    var body: some View {
        Text(entries)
            .multilineTextAlignment(.leading)
            .lineLimit(10)
            .onAppear { entries = Self.fetchEntries() }
    }

    @MainActor
    private static func fetchEntries() -> String {
        let osLogEntries = try? store?.getEntries(with: [.reverse], at: oneMinuteAgo, matching: predicate)
        return osLogEntries?.map { "\($0.composedMessage) \n" }.joined() ?? ""
    }
}

struct LogView_Previews: PreviewProvider {
    static var previews: some View {
        LogView()
    }
}
