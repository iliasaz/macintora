import SwiftUI

/// One-shot alert presented on first launch when the user has a pre-existing
/// `tnsnames.ora` but no entries in the new ``ConnectionStore``. Offers to
/// import the file. Decision is remembered in `UserDefaults` so users who
/// dismiss it never see it again.
///
/// Attached as a modifier on `MainDocumentView` (the first view a user sees
/// after launch). Documents created later in the same session don't re-fire
/// it because the gate is checked once per app process.
struct TnsImportPromptModifier: ViewModifier {
    @Environment(\.connectionStore) private var injectedStore
    @AppStorage("tnsImportPromptShown") private var promptShown = false
    @State private var showAlert = false
    @State private var importedCount: Int = 0

    private static let defaultTnsnamesPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.oracle/tnsnames.ora"

    func body(content: Content) -> some View {
        content
            .onAppear { evaluate() }
            .alert(
                "Import existing connections from tnsnames.ora?",
                isPresented: $showAlert
            ) {
                Button("Import") { performImport() }
                Button("Skip", role: .cancel) { promptShown = true }
            } message: {
                Text("Macintora found \(Self.defaultTnsnamesPath). Importing creates a saved connection for each entry so you no longer need the file.")
            }
            .alert(
                "Imported \(importedCount) \(importedCount == 1 ? "connection" : "connections")",
                isPresented: importedAlertBinding
            ) {
                Button("OK") { importedCount = 0 }
            }
    }

    private var importedAlertBinding: Binding<Bool> {
        Binding(
            get: { importedCount > 0 },
            set: { if !$0 { importedCount = 0 } }
        )
    }

    private func evaluate() {
        guard !promptShown,
              let store = injectedStore,
              store.connections.isEmpty,
              FileManager.default.fileExists(atPath: Self.defaultTnsnamesPath)
        else { return }
        showAlert = true
    }

    private func performImport() {
        guard let store = injectedStore else { return }
        importedCount = store.importFromTnsnames(at: Self.defaultTnsnamesPath)
        promptShown = true
    }
}

extension View {
    /// Show the one-time tnsnames.ora import prompt on first launch.
    func tnsImportPromptOnFirstLaunch() -> some View {
        modifier(TnsImportPromptModifier())
    }
}
