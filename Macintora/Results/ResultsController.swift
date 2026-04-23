import Foundation
import OracleNIO

@MainActor
final class ResultsController: ObservableObject {
    weak var document: MainDocumentVM?
    var results: [String: ResultViewModel]
    @Published var isExecuting = false

    init(document: MainDocumentVM) {
        self.document = document
        self.results = [:]
        addResultVM()
    }

    func addResultVM() {
        self.results = ["current": ResultViewModel(parent: self)]
    }

    func runSQL(_ runnableSQL: RunnableSQL) {
        let resultVM = results["current"]!
        guard let conn = document?.conn else { return }
        resultVM.promptForBindsAndExecute(for: runnableSQL, using: conn)
    }

    func explainPlan(for sql: String) {
        let resultVM = results["current"]!
        guard let conn = document?.conn else { return }
        resultVM.explainPlan(for: sql, using: conn)
    }

    func compileSource(for runnableSQL: RunnableSQL) {
        let resultVM = results["current"]!
        guard let conn = document?.conn else { return }
        resultVM.compileSource(for: runnableSQL, using: conn)
    }

    func cancelCurrent() {
        let resultVM = results["current"]!
        resultVM.cancel()
    }

    func displayError(_ error: Error) {
        let resultVM = results["current"]!
        resultVM.displayError(AppDBError.from(error))
    }

    func clearError() {
        let resultVM = results["current"]!
        resultVM.clearError()
    }
}
