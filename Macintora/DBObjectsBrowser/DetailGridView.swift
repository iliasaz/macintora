//
//  DetailGridView.swift
//  DBObjectsBrowser
//
//  Created by Ilia on 6/20/22.
//

import CoreData
import SwiftUI
import AppKit
import os

struct DetailGridView: NSViewRepresentable {
    @Environment(\.colorScheme) var colorScheme
    @State var rows: [NSManagedObject]
    var columnLabels: [String]
    var booleanColumnLabels: [String]
    var autoColWidth = true
    
    init(rows: [NSManagedObject], columnLabels: [String], booleanColumnLabels: [String] = [], rowSortFn: (NSManagedObject, NSManagedObject) -> Bool) {
        _rows = State(initialValue: rows.sorted(by: rowSortFn) )
        self.columnLabels = columnLabels
        self.booleanColumnLabels = booleanColumnLabels
    }
    
    mutating func sort(by colName: String?, ascending: Bool) {
        guard let colName = colName, rows.count > 0 else { return }
        let sampleValue = self.rows[0].value(forKey: colName)
        let sortFn: (NSManagedObject, NSManagedObject) -> Bool
        switch sampleValue {
            case is String:
                sortFn = {
                    (lhs:NSManagedObject , rhs: NSManagedObject) in
                    (lhs.value(forKey: colName) as! String) < (rhs.value(forKey: colName) as! String)
                }
            case is NSNumber:
                sortFn = {
                    (lhs:NSManagedObject , rhs: NSManagedObject) in
                    (lhs.value(forKey: colName) as! NSNumber).compare(rhs.value(forKey: colName) as! NSNumber) == .orderedAscending
                }
            case is Int16:
                sortFn = {
                    (lhs:NSManagedObject , rhs: NSManagedObject) in
                    (lhs.value(forKey: colName) as! Int16) < (rhs.value(forKey: colName) as! Int16)
                }
            case is Int32:
                sortFn = {
                    (lhs:NSManagedObject , rhs: NSManagedObject) in
                    (lhs.value(forKey: colName) as! Int32) < (rhs.value(forKey: colName) as! Int32)
                }
            case is Int64:
                sortFn = {
                    (lhs:NSManagedObject , rhs: NSManagedObject) in
                    (lhs.value(forKey: colName) as! Int64) < (rhs.value(forKey: colName) as! Int64)
                }
            case is Bool:
                sortFn = {
                    (lhs:NSManagedObject , rhs: NSManagedObject) in
                    lhs.value(forKey: colName) as! Bool
                }
            default:
                sortFn = { (_, _) in return false }
        }
        if ascending { rows.sort(by: sortFn) } else { rows.sort(by: sortFn); rows.reverse() }
    }
    
    func makeCoordinator() -> DetailGridViewCoordinator {
        DetailGridViewCoordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        //        log.viewcycle.debug("in makeNSView")
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
        
        // attach to a scrollview
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.documentView = tableView
        return scrollView
    }
    
//    private func computeIntrisicSize(_ view: LegalMentionView) {
//        let targetSize = CGSize(width: desiredWidth, height: UIView.layoutFittingCompressedSize.height)
//        let fittingSize = view.systemLayoutSizeFitting(targetSize,
//                                                       withHorizontalFittingPriority: .defaultHigh,
//                                                       verticalFittingPriority: .fittingSizeLevel)
//        computedHeight = fittingSize.height
//    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        //        log.viewcycle.debug("in updateNSView")
        let tableView = (nsView.documentView as! TableViewWithPasteboard)
        let coordinator = tableView.delegate as! DetailGridViewCoordinator
        tableView.beginUpdates()
        tableView.reloadData()
        //        log.viewcycle.debug("reload complete, row count: \(tableView.numberOfRows)")
        coordinator.populateColumnHeaders()
        tableView.endUpdates()
        //        log.viewcycle.debug("populateColumnHeaders complete")
    }
}


class DetailGridViewCoordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
    var parent: DetailGridView
    
    weak var tableView: TableViewWithPasteboard?
    
    init(_ parent: DetailGridView) {
        self.parent = parent
    }
    
    func didColumnsChange() -> Bool {
        guard let tableView = tableView else {
            return false
        }
        guard tableView.tableColumns.count == parent.columnLabels.count else { return true }
        
        for (index, tabCol) in tableView.tableColumns.enumerated() {
            if tabCol.title != parent.columnLabels[index] { return true }
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
            //            log.viewcycle.debug("in populateColumnHeaders, columns changed, old columns: \( (tableView.tableColumns.map {$0.title}).joined(separator: ",") )")
            for c in tableView.tableColumns {
                tableView.removeTableColumn(c)
            }
            tableView.columnWidths.removeAll()
            //            log.viewcycle.debug("columns removed")
            for col in parent.columnLabels {
                let tabCol = NSTableColumn(identifier: .init(col))
                tabCol.title = col
                tabCol.minWidth = Constants.minColumnWidth
                tabCol.maxWidth = Constants.maxColumnWidth
                tabCol.sizeToFit()
                tabCol.width += 20
                tabCol.sortDescriptorPrototype = NSSortDescriptor(key: col, ascending: true)
                //            tabCol.headerToolTip = "tooltip: \(col.lowercased())"
                tabCol.headerCell.attributedStringValue = NSAttributedString(string: col, attributes: [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: 12), NSAttributedString.Key.foregroundColor: NSColor.systemBlue])
                
                tableView.addTableColumn(tabCol)
                tableView.columnWidths.append(tabCol.width)
            }
            //            log.viewcycle.debug("columns added: \(tableView.tableColumns.count)")
        }
        //        log.viewcycle.debug("in populateColumnHeaders, columns NOT changed, columns:  \( (tableView.tableColumns.map {$0.title}).joined(separator: ",") )")
        //        log.viewcycle.debug("auto flag: \(self.parent.autoColWidth)")
        if parent.autoColWidth && tableView.numberOfRows > 0 {
            for (idx, _) in tableView.tableColumns.enumerated() {
                sizeToFit(column: idx)
            }
            //            log.viewcycle.debug("new column widths: \(tableView.columnWidths)")
        }
        //        log.viewcycle.debug("exiting populateColumnHeaders")
    }
    
    func sizeToFit(column: Int) {
        guard let tableView = self.tableView else {
            return
        }
        if let view = tableView.view(atColumn: column, row: 0, makeIfNecessary: true) as? NSTableCellView {
            let colName = tableView.tableColumns[column].identifier.rawValue
            var width = tableView.tableColumns[column].width
            for row in parent.rows {
                view.textField?.objectValue = row.value(forKey: colName)
                let size = view.textField?.fittingSize ?? CGSize(width: 0.0, height: 0.0)
                //                log.viewcycle.debug("col \(column) original width: \(tableView.tableColumns[column].width), new width: \(max(width, size.width))")
                width = max(width, size.width)
            }
            tableView.tableColumns[column].width = width
        }
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        //        log.viewcycle.debug("numberOfRows: \(self.parent.rows.count)")
        return parent.rows.count
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
        
        var cell: NSView //NSTableCellView
        guard let cellIdentifier = tableColumn?.identifier else { return nil }
        // find a cell object in cache
        if let existingCell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) {
            cell = existingCell // NSTableCellView
        } else {
            switch cellIdentifier.rawValue {
                case parent.booleanColumnLabels:
                    cell = makeTableCellViewBoolean(identifier: cellIdentifier)
                default:
                    cell = makeTableCellViewTextField(identifier: cellIdentifier)
            }
        }
        return cell
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        20.0
    }
    
    func tableView(_ tableView: NSTableView, sizeToFitWidthOfColumn column: Int) -> CGFloat {
        return tableView.tableColumns[column].width
    }
    
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let sortDescriptor = tableView.sortDescriptors.first else { return }
        parent.sort(by: sortDescriptor.key, ascending: sortDescriptor.ascending)
        tableView.reloadData()
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        return parent.rows[row].value(forKey: tableColumn!.identifier.rawValue)
    }
    
    func getRowTSV(rowNumber: Int) -> String {
        // no quotes around fields
        return parent.columnLabels.map { "\(parent.rows[rowNumber].value(forKey: $0) ?? "(null)")" }.joined(separator: "\t")
    }
    
    func getSelectedRowsTSV() -> String {
        return tableView!.selectedRowIndexes.compactMap { getRowTSV(rowNumber: $0) }.joined(separator: "\n")
    }
}


//class TableViewWithPasteboard: NSTableView, NSMenuItemValidation {
//
//    // this is needed to teach our table view respond to Cmd-C
//    override var acceptsFirstResponder: Bool { true }
//    var columnWidths = [CGFloat]()
//
//    // Cmd-C reponder
//    @objc func copy(_ sender: AnyObject?) {
//        //        let coordinator = self.delegate as! DetailGridViewCoordinator
//        // get selected rows, for each row get CSV representation
//        let textToDisplayInPasteboard = "test" // coordinator.getSelectedRowsCSV()
//                                               // put them into a pasteboard
//        let pasteBoard = NSPasteboard.general
//        pasteBoard.clearContents()
//        pasteBoard.setString(textToDisplayInPasteboard, forType:NSPasteboard.PasteboardType.string)
//    }
//
//    // this is needed to teach our table view respond to Cmd-C
//    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
//        switch menuItem.identifier {
//            case NSUserInterfaceItemIdentifier("copy:"):
//                // enable Copy if at least one row is selected
//                return numberOfSelectedRows > 0
//            default:
//                return false
//        }
//    }
//}

class CheckBox: NSButton {
    var isUserInteractionEnabled = false
    @objc public var checked: Bool {
        get { return state == NSControl.StateValue.on }
        set { state = newValue ? NSControl.StateValue.on : NSControl.StateValue.off }
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        return isUserInteractionEnabled ? super.hitTest(point) : nil
    }
}
