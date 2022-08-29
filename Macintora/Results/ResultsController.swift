//
//  ResultsController.swift
//  Macintora
//
//  Created by Ilia Sazonov on 7/1/22.
//

import Foundation
import SwiftOracle

class ResultsController: ObservableObject {
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
        log.debug("in ResultsController.runSQL")
        let resultVM = results["current"]!
        guard let conn = document?.conn else { return }
//        let testConn = Connection(service: OracleService(from_string: "test"), user: "test", pwd: "test")
        resultVM.promptForBindsAndExecute(for: runnableSQL, using: conn)
    }
    
    func explainPlan(for sql: String) {
        log.debug("in ResultsController.explainPlan")
        let resultVM = results["current"]!
        guard let conn = document?.conn else { return }
        resultVM.explainPlan(for: sql, using: conn)
    }
    
    func compileSource(for runnableSQL: RunnableSQL) {
        log.debug("in ResultsController.explainPlan")
        let resultVM = results["current"]!
        guard let conn = document?.conn else { return }
        resultVM.compileSource(for: runnableSQL, using: conn)
    }
    
    @MainActor func displayError(_ error: Error) {
        let resultVM = results["current"]!
        resultVM.displayError(error)
    }
    
    @MainActor func clearError() {
        let resultVM = results["current"]!
        resultVM.clearError()
    }
}
