//
//  SessionView.swift
//  SessionBrowser
//
//  Created by Ilia on 6/20/22.
//

import CoreData
import SwiftUI
import AppKit
import os

struct SessionView: NSViewRepresentable {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var model: SBVM
    var autoColWidth = true
    
    typealias Coordinator = SessionViewCoordinator
    
    func makeCoordinator() -> SessionViewCoordinator {
        SessionViewCoordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let tableView = TableViewWithPasteboard()
        
        // attach coordinator
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.target = context.coordinator
        tableView.copyFormatter = context.coordinator.getSelectedRowsTSV
        context.coordinator.tableView = tableView
        
        // set columns
        context.coordinator.populateColumnHeaders()
        
        // little goodies
        tableView.intercellSpacing = NSSize(width: 5, height: 0)
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.style = .inset //.automatic
        tableView.usesStaticContents = false
        tableView.usesAutomaticRowHeights = false
        tableView.columnAutoresizingStyle = .sequentialColumnAutoresizingStyle
        
        // context menu
        let contextMenu = NSMenu(title: "Context")
        let menuStartTrace = NSMenuItem(title: "Start Tracing", action: #selector(SessionViewCoordinator.startSessionTrace(_:)), keyEquivalent: "")
        menuStartTrace.target = context.coordinator
        
        let menuStopTrace = NSMenuItem(title: "Stop Tracing", action: #selector(SessionViewCoordinator.stopSessionTrace(_:)), keyEquivalent: "")
        menuStopTrace.target = context.coordinator
        
//        let menuStartSqlMonitor = NSMenuItem(title: "Start SQL Monitor", action: #selector(SessionViewCoordinator.startSqlMonitor(_:)), keyEquivalent: "")
//        menuStartSqlMonitor.target = context.coordinator
//
//        let menuStopSqlMonitor = NSMenuItem(title: "Stop SQL Monitor", action: #selector(SessionViewCoordinator.stopSqlMonitor(_:)), keyEquivalent: "")
//        menuStopSqlMonitor.target = context.coordinator
        
        let menuKillSession = NSMenuItem(title: "Kill Session", action: #selector(SessionViewCoordinator.killSession(_:)), keyEquivalent: "")
        menuKillSession.target = context.coordinator
        
        let menuRefresh = NSMenuItem(title: "Copy Trace File Name", action: #selector(SessionViewCoordinator.copyTraceFileName(_:)), keyEquivalent: "")
        menuRefresh.target = context.coordinator

        contextMenu.addItem(menuStartTrace)
        contextMenu.addItem(menuStopTrace)
//        contextMenu.addItem(menuStartSqlMonitor)
//        contextMenu.addItem(menuStopSqlMonitor)
        contextMenu.addItem(menuKillSession)
        contextMenu.addItem(menuRefresh)
        
        tableView.menu = contextMenu
        
        // attach to a scrollview
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.documentView = tableView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let tableView = (nsView.documentView as! TableViewWithPasteboard)
        let coordinator = tableView.delegate as! SessionViewCoordinator
        tableView.beginUpdates()
        tableView.reloadData()
        coordinator.populateColumnHeaders()
        tableView.endUpdates()
    }
}


class SessionViewCoordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
    var parent: SessionView
    
    weak var tableView: TableViewWithPasteboard?
    
    init(_ parent: SessionView) {
        self.parent = parent
    }
    
    @objc func startSessionTrace(_ sender: Any) {
        log.viewCycle.debug("starting session trace for row \(self.tableView?.clickedRow ?? -1)")
        let row = self.tableView!.clickedRow
        let sid = parent.model.rows[row]["SID"]!.int!
        let serial = parent.model.rows[row]["SERIAL#"]!.int!
        self.parent.model.startTrace(sid: sid, serial: serial)
    }
    
    @objc func stopSessionTrace(_ sender: Any) {
        log.viewCycle.debug("stopping session trace for row \(self.tableView?.clickedRow ?? -1)")
        self.parent.model.stopTrace(sid: parent.model.rows[self.tableView!.clickedRow]["SID"]!.int!, serial: parent.model.rows[self.tableView!.clickedRow]["SERIAL#"]!.int!)
    }
    
//    @objc func startSqlMonitor(_ sender: Any) {
//        log.viewCycle.debug("starting session trace for row \(self.tableView?.clickedRow ?? -1)")
//        self.parent.model.startSqlMonitor(sid: parent.model.rows[self.tableView!.clickedRow]["SID"]!.int!, serial: parent.model.rows[self.tableView!.clickedRow]["SERIAL#"]!.int!)
//    }
//
//    @objc func stopSqlMonitor(_ sender: Any) {
//        log.viewCycle.debug("stopping session trace for row \(self.tableView?.clickedRow ?? -1)")
//        self.parent.model.stopSqlMonitor(sid: parent.model.rows[self.tableView!.clickedRow]["SID"]!.int!, serial: parent.model.rows[self.tableView!.clickedRow]["SERIAL#"]!.int!)
//    }
    
    @objc func killSession(_ sender: Any) {
        log.viewCycle.debug("killing session for row \(self.tableView?.clickedRow ?? -1)")
        self.parent.model.killSession(sid: parent.model.rows[self.tableView!.clickedRow]["SID"]!.int!, serial: parent.model.rows[self.tableView!.clickedRow]["SERIAL#"]!.int!)
    }
    
    @objc func copyTraceFileName(_ sender: Any) {
        log.viewCycle.debug("Refreshing sessions")
        let row = self.tableView!.clickedRow
        let processAddr = parent.model.rows[row]["PADDR"]!.string!
        let instanceNumber = parent.model.rows[row]["INST_ID"]!.int!
        self.parent.model.copyTraceFileName(paddr: processAddr, instNum: instanceNumber)
    }

    func didColumnsChange() -> Bool {
        guard let tableView = tableView else {
            return false
        }
        guard tableView.tableColumns.count == parent.model.columnLabels.count else { return true }
        
        for (index, tabCol) in tableView.tableColumns.enumerated() {
            if tabCol.title != parent.model.columnLabels[index] { return true }
        }
        return false
    }
    
    func populateColumnHeaders() {
        // define columns
        guard let tableView = self.tableView else {
            return
        }
        
        if didColumnsChange() {
            // updating columns
            for c in tableView.tableColumns {
                tableView.removeTableColumn(c)
            }
            tableView.columnWidths.removeAll()
            for col in parent.model.columnLabels {
                let tabCol = NSTableColumn(identifier: .init(col))
                tabCol.title = col
                tabCol.minWidth = Constants.minColumnWidth
                tabCol.maxWidth = Constants.maxColumnWidth
                tabCol.sizeToFit()
                tabCol.width += 20
                tabCol.sortDescriptorPrototype = NSSortDescriptor(key: col, ascending: true)
                tabCol.headerCell.attributedStringValue = NSAttributedString(string: col, attributes: [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: 12), NSAttributedString.Key.foregroundColor: NSColor.systemBlue])
                tableView.addTableColumn(tabCol)
                tableView.columnWidths.append(tabCol.width)
            }
        }
        if parent.autoColWidth && tableView.numberOfRows > 0 {
            for (idx, _) in tableView.tableColumns.enumerated() {
                sizeToFit(column: idx)
            }
        }
    }
    
    func sizeToFit(column: Int) {
        guard let tableView = self.tableView else {
            return
        }
        if let view = tableView.view(atColumn: column, row: 0, makeIfNecessary: true) as? NSTableCellView {
            let colName = tableView.tableColumns[column].identifier.rawValue
            var width = tableView.tableColumns[column].width
            for row in parent.model.rows {
                view.textField?.objectValue = row[colName]?.valueString
                let size = view.textField?.fittingSize ?? CGSize(width: 0.0, height: 0.0)
                width = max(width, size.width)
            }
            tableView.tableColumns[column].width = width
        }
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return parent.model.rows.count
    }
    
    
    func makeTableCellViewTextField(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let text = NSTextField()
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.isBordered = false
        text.translatesAutoresizingMaskIntoConstraints = false
        text.font = NSFont(name: "Source Code Pro", size: NSFont.systemFontSize)
        text.placeholderString = "this is a text field"
        text.maximumNumberOfLines = 1
        text.preferredMaxLayoutWidth = 400
        
        let cell = NSTableCellView()
        cell.textField = text
        cell.addSubview(text)
        cell.autoresizingMask = .width
        cell.identifier = identifier
        
        // bind text field to cell's objectValue, which is auto-magically populated
        // by tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? (see below)
        cell.textField?.bind(.value , to: cell, withKeyPath: "objectValue", options: nil)
        
        cell.addConstraint(NSLayoutConstraint(item: text, attribute: .centerY, relatedBy: .equal, toItem: cell, attribute: .centerY, multiplier: 1, constant: 0))
        cell.addConstraint(NSLayoutConstraint(item: text, attribute: .leading, relatedBy: .equal, toItem: cell, attribute: .leading, multiplier: 1, constant: 0))
        return cell
    }
    
    func makeTableCellViewBoolean(identifier: NSUserInterfaceItemIdentifier) -> NSView {
        let control = CheckBox()
        control.translatesAutoresizingMaskIntoConstraints = false
        control.autoresizingMask = .width
        control.identifier = identifier
        control.setButtonType(.switch)
        control.alignment = .center
        control.title = ""
        return control
    }
    
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        
        var cell: NSTableCellView
        let cellIdentifier = NSUserInterfaceItemIdentifier("cell")
        // find a cell object in cache
        if let existingCell = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) {
            cell = existingCell as! NSTableCellView
        } else {
            cell = makeTableCellViewTextField(identifier: cellIdentifier)
        }
        // make the row number not selectable so it's easier to click
        if tableColumn?.identifier.rawValue == "#" {
            cell.textField?.isSelectable = false
        }
        // set the value; this can be commented out if using bindings
        return cell
    }
    
    func tableView(_ tableView: NSTableView, sizeToFitWidthOfColumn column: Int) -> CGFloat {
        return tableView.tableColumns[column].width
    }
    
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let sortDescriptor = tableView.sortDescriptors.first else { return }
        parent.model.sort(by: sortDescriptor.key, ascending: sortDescriptor.ascending)
        tableView.reloadData()
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        if tableColumn?.identifier.rawValue == "#" {
            return row+1
        } else {
            return parent.model.rows[row][tableColumn!.identifier.rawValue]?.valueString
        }
    }
    
    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
        highlightRow(rowView: rowView, forRow: row)
    }
    
    func highlightRow(rowView: NSTableRowView, forRow row: Int, force: Bool = false) {
//        if row > 4 { return }
//        log.viewCycle.debug("row: \(row), force: \(force), sid: \(self.parent.model.rows[row]["SID"]!.int ?? -1), mainSid: \(self.parent.model.mainConnection.mainSession?.sid ?? -1)")
        // highlight active trace
        if parent.model.rows[row]["SQL_TRACE"]!.string == "ENABLED" || force {
            rowView.backgroundColor = .findHighlightColor
            return
        }
        // highlight main session
        if parent.model.rows[row]["SID"]!.int == parent.model.mainConnection.mainSession?.sid &&
            parent.model.rows[row]["SERIAL#"]!.int == parent.model.mainConnection.mainSession?.serial || force {
            rowView.backgroundColor = .green.withAlphaComponent(0.3)
            return
        }
        // highlight this session
        if parent.model.rows[row]["SID"]!.int == parent.model.oraSession?.sid &&
            parent.model.rows[row]["SERIAL#"]!.int == parent.model.oraSession?.serial || force {
            rowView.backgroundColor = .scrubberTexturedBackground
            return
        }
        // highlight waiting sessions
        if parent.model.rows[row]["WAIT_CLASS"]!.string != "Idle" {
            switch parent.model.rows[row]["STATE"]!.string {
                case "WAITING": rowView.backgroundColor = .orange.withAlphaComponent(0.3)
                case "WAITED SHORT TIME": rowView.backgroundColor = .orange.withAlphaComponent(0.1)
                default: break
            }
            if !parent.model.rows[row]["BLOCKING_SESSION"]!.valueString.isEmpty {
                rowView.backgroundColor = .systemPink.withAlphaComponent(0.5)
            }
        }
    }
    
    func getRowTSV(rowNumber: Int) -> String {
        // no quotes around fields
        return (parent.model.rows[rowNumber].fields.map { "\($0.valueString)" }).joined(separator: "\t")
    }
    
    func getSelectedRowsTSV() -> String {
        return tableView!.selectedRowIndexes.compactMap { getRowTSV(rowNumber: $0) }.joined(separator: "\n")
    }
}



