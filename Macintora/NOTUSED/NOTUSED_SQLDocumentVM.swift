//
//  SQLDocumentVM.swift
//  MacOra
//
//  Created by Ilia on 3/12/22.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Combine
import SwiftOracle
import CodeEditor


//extension UTType {
//    static var macora: UTType {
//        UTType(importedAs: "com.iliasazonov.macora")
//    }
//}


class SQLDocumentVM: ReferenceFileDocument {
    
    typealias Snapshot = MainModel
    static var readableContentTypes: [UTType] { [.macora] }
    static var writableContentTypes: [UTType] { [.macora] }
    
    var model: MainModel
//    var editorSelectionRange: Range<String.Index> = "".startIndex..<"".endIndex
    
    func snapshot(contentType: UTType) throws -> MainModel {
        model
    }
    
    func fileWrapper(snapshot: MainModel, configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(snapshot)
        let fileWrapper = FileWrapper(regularFileWithContents: data)
        return fileWrapper
    }
    
    init(text: String = "select user, systimestamp from dual;") {
        self.model = MainModel(text: text)
    }
    
    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        log.debug("loading model")
        self.model = try JSONDecoder().decode(MainModel.self, from: data)
        log.debug("model loaded")
    }
    
    // MARK: - Intent functions
    
    func connect() {
    
    }
    
    func disconnect() {

    }
    
    func runCurrentSQL() async {
        
    }
    
    func refreshQueryResults() async {
        
    }
    
    func backgroundAction() {
        
    }
    
}
