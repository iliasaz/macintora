//
//  QueryResultViewWrapper.swift
//  MacOra
//
//  Created by Ilia on 12/23/21.
//

import SwiftUI
import AppKit

struct ResultViewWrapper: View {
    @ObservedObject var queryResults: ResultViewModel
    var resultsController: ResultsController
    
    init(resultsController: ResultsController) {
        self.resultsController = resultsController
        queryResults = resultsController.results["current"]!
    }
    
    var body: some View {
        VStack {
            let _ = log.viewCycle.debug("Redrawing ResultViewWrapper, queryResults: \(queryResults.bindVarVM)")
            queryResultToolbar
            ZStack {
                GeometryReader { geo in
                    HStack {
                        ResultView(model: self.queryResults )
                            .frame(maxWidth: .infinity, minHeight: 200)
                        
                        BindVarInputView(bindVarVM: $queryResults.bindVarVM, runAction: runWithBinds, cancelAction: {queryResults.showingBindVarInputView = false})
                            .frame(width: queryResults.showingBindVarInputView ? geo.size.width/3 : 0, alignment: .trailing)
                            .hidden(!queryResults.showingBindVarInputView)
                        
                        RunningLogView(attributedText: queryResults.runningLogStr)
                            .frame(width: queryResults.showingLog ? geo.size.width/3 : 0, alignment: .trailing)
                    }
                }
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .frame(minHeight: 200)
                    .hidden(!queryResults.resultsController.isExecuting)
            }
        }
        .padding(.vertical)
    }
    
    func runWithBinds() {
        log.viewCycle.debug("in runWithBinds, values from the view:")
        queryResults.showingBindVarInputView = false
        queryResults.runCurrentSQL(using: (resultsController.document?.conn)!)
    }
    
    
    @State var sqlShown = false
    var queryResultToolbar: some View {
        HStack(spacing: 2) {
//            Button {} label: { Image(systemName: "laptopcomputer.and.arrow.down").foregroundColor(Color.blue)}
//            .help("export")
            
            Button {
                sqlShown.toggle()
            } label: { Text("SQL").foregroundColor(Color.blue)}
            .help("show SQL")
            .sheet(isPresented: $sqlShown) {
                VStack {
                    Text("SQL ID: \(queryResults.sqlId)")
                        .textSelection(.enabled)
                    Text(queryResults.currentSql)
                        .textSelection(.enabled)
                        .lineLimit(10)
                        .frame(width: 300.0, height: 200.0, alignment: .topLeading)
                        .padding()
                    Button { sqlShown.toggle() } label: { Text("Dismiss") }
                    .padding()
                }.padding()
            }
            
            Toggle("Auto Width", isOn: $queryResults.autoColWidth).toggleStyle(.switch)
                .padding(.horizontal)
            
            Form {
                TextField(value: $queryResults.rowFetchLimit, formatter: NumberFormatter()) {
                    Text("Max Rows")
                }
                .textFieldStyle(.roundedBorder)
                .frame(width: 120, alignment: .leading)
            }
            Button {
                
            } label: {
                Image(systemName: "arrow.clockwise").foregroundColor(Color.blue)
            }
            .help("Refresh")
            
            Toggle(isOn: $queryResults.showingLog) {
                Image(systemName: "list.dash") //.foregroundColor(Color.blue)
            }
            .toggleStyle(.button)
            .help("Show log")
            
            Spacer()
        }
        .padding(.horizontal, 3)
    }
}

struct RunningLogView: NSViewRepresentable {
    typealias NSViewType = NSScrollView
    
    var attributedText: NSAttributedString?
    let isSelectable: Bool = true
    var insetSize: CGSize = .zero
    
    func makeNSView(context: Context) -> NSViewType {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.drawsBackground = false
        textView.textColor = .controlTextColor
        textView.textContainerInset = insetSize
        scrollView.drawsBackground = true
        return scrollView
    }
    
    func updateNSView(_ nsView: NSViewType, context: Context) {
        let textView = (nsView.documentView as! NSTextView)
        textView.isSelectable = isSelectable
        
        if let attributedText = attributedText,
           attributedText != textView.attributedString() {
            textView.textStorage?.setAttributedString(attributedText)
        }
        
        if let lineLimit = context.environment.lineLimit {
            textView.textContainer?.maximumNumberOfLines = lineLimit
        }
    }
}

//struct QueryResultViewWrapper_Previews: PreviewProvider {
//    static var previews: some View {
//        QueryResultViewWrapper(queryResults: QueryResultViewModel())
//    }
//}
