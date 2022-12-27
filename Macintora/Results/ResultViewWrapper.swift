//
//  QueryResultViewWrapper.swift
//  MacOra
//
//  Created by Ilia on 12/23/21.
//

import SwiftUI
import AppKit
import Combine

struct ResultViewWrapper: View {
    @ObservedObject var queryResults: ResultViewModel
    var resultsController: ResultsController
    @State private var dbTimeStr = ""
    @State private var dbTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var isDbTimerRunning = false
    @AppStorage("serverTimeSeconds") private var serverTimeSeconds = false
    
    let dateFormatter: DateFormatter = DateFormatter()

    
    init(resultsController: ResultsController) {
        self.resultsController = resultsController
        queryResults = resultsController.results["current"]!
        dateFormatter.calendar = Calendar(identifier: .iso8601)
        dateFormatter.dateFormat = serverTimeSeconds ? "yyyy-MM-dd HH:mm:ss" : "yyyy-MM-dd HH:mm"
        dateFormatter.timeZone = resultsController.document?.mainConnection.mainSession?.dbTimeZone
    }
    
    func stopDBTimer() {
        self.dbTimer.upstream.connect().cancel()
        log.viewCycle.debug(("stopped timer"))
    }
        
    func startDBTimer() {
        dateFormatter.dateFormat = serverTimeSeconds ? "yyyy-MM-dd HH:mm:ss" : "yyyy-MM-dd HH:mm"
        dateFormatter.timeZone = resultsController.document?.mainConnection.mainSession?.dbTimeZone
        log.viewCycle.debug(("started timer"))
        self.dbTimer = Timer.publish(every: serverTimeSeconds ? 1 : 60, on: .main, in: .common).autoconnect()
    }

    func updateTimerDisplay(with input: Date) {
//        log.viewCycle.debug("received timer input: \(input), \(dateFormatter.string(from: input))")
        if isDbTimerRunning {
            dbTimeStr = dateFormatter.string(from: input)
        } else { dbTimeStr = "" }
    }
    
    var body: some View {
        VStack {
//            let _ = log.viewCycle.debug("Redrawing ResultViewWrapper, queryResults: \(queryResults.bindVarVM)")
            queryResultToolbar
            GeometryReader { geo in
                HStack {
                    ZStack {
                        ResultView(model: self.queryResults )
                            .frame(maxWidth: .infinity, minHeight: 100, maxHeight: .infinity)
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .frame(minHeight: 100)
                            .hidden(!queryResults.resultsController.isExecuting)
                    }
                    if queryResults.showingBindVarInputView {
                        BindVarInputView(bindVarVM: $queryResults.bindVarVM, runAction: runWithBinds, cancelAction: {queryResults.showingBindVarInputView = false})
                            .frame(width: queryResults.showingBindVarInputView ? geo.size.width/3 : 0, alignment: .trailing)
//                                .hidden(!queryResults.showingBindVarInputView)
                    }
                    
                    RunningLogView(attributedText: queryResults.runningLogStr)
                        .frame(width: queryResults.showingLog ? geo.size.width/3 : 0, alignment: .trailing)
                }
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
            Group {
                Button {
                    self.queryResults.refreshData()
                } label: {
                    Image(systemName: "arrow.clockwise").foregroundColor(Color.blue)
                }
                .help("Refresh")
                
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
                    self.queryResults.fetchMoreData()
                } label: {
                    Image(systemName: "forward")
                }
                .help("More Data")
                
                Button {
                    self.queryResults.getSQLCount()
                } label: {
                    Image(systemName: "sum") //.foregroundColor(Color.blue)
                }
                .help("Count")
                
                Text(self.queryResults.sqlCount, format: .number)
                    .padding(.horizontal, 3)
            }
            
            Menu {
                Button {
                    guard let saveURL = showSavePanel(defaultName: "query1.csv") else { return }
                    queryResults.export(to: saveURL, type: .csv)
                } label: { Text("CSV")}
                
                Button {
                    guard let saveURL = showSavePanel(defaultName: "query1.txt") else { return }
                    queryResults.export(to: saveURL, type: .tsv)
                } label: { Text("TSV")}
                
                Button {
                    guard let saveURL = showSavePanel(defaultName: "query1.txt") else { return }
                    queryResults.export(to: saveURL, type: .none)
                } label: { Text("None")}
            } label: {
                Label("Export", systemImage: "laptopcomputer.and.arrow.down")
            }
            .fixedSize()
            .menuStyle(ButtonMenuStyle())
            .help("export ")
                
            
            Spacer()
            serverTimeToolbar
            
            Toggle(isOn: $queryResults.showingLog) {
                Image(systemName: "list.dash") //.foregroundColor(Color.blue)
            }
            .toggleStyle(.button)
            .padding(.horizontal)
            .help("Show log")

        }
        .padding(.horizontal, 3)
        .onAppear() { stopDBTimer() }
    }
    
    var serverTimeToolbar: some View {
        HStack(spacing: 2) {
            
            Toggle(isOn: $isDbTimerRunning) {
                Label("\(dbTimeStr.isEmpty ? "server time" : dbTimeStr)", systemImage: "clock")
                    .onReceive(dbTimer) { input in
                        updateTimerDisplay(with: input)
                    }
            }
                .toggleStyle(.button)
                .labelStyle(.titleAndIcon)
                .onChange(of: isDbTimerRunning) { newValue in
                    log.viewCycle.debug("onChange of isDbTimerRunning: \(newValue)")
                    if newValue { startDBTimer(); updateTimerDisplay(with: .now) }
                    else { stopDBTimer() }
                }
                .disabled(resultsController.document?.isConnected != .connected)
        }
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
