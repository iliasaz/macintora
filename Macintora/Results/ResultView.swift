//
//  QueryResultView.swift
//  MacOra
//
//  Created by Ilia on 10/25/21.
//

import SwiftUI
import AppKit

struct ResultView: NSViewRepresentable {
    @ObservedObject var model: ResultViewModel
    @Environment(\.colorScheme) var colorScheme
    
    func makeCoordinator() -> ResultViewCoordinator {
        ResultViewCoordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        log.viewCycle.debug("in makeNSView")
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
        
//        tableView.gridStyleMask = [.solidVerticalGridLineMask, .solidHorizontalGridLineMask]
//        tableView.gridColor = NSColor.blue
        tableView.style = .inset
        tableView.usesStaticContents = false
        tableView.usesAutomaticRowHeights = true
        tableView.columnAutoresizingStyle = .sequentialColumnAutoresizingStyle
        tableView.awakeFromNib()
        // attached a scrollview
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.documentView = tableView
        return scrollView
    }
    
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard model.dataHasChanged else {return}
        log.viewCycle.debug("in updateNSView")
        let tableView = (nsView.documentView as! TableViewWithPasteboard)
        let coordinator = tableView.delegate as! ResultViewCoordinator
        tableView.beginUpdates()
        tableView.reloadData()
        log.viewCycle.debug("updateNSView: reload complete, row count: \(tableView.numberOfRows)")
        coordinator.populateColumnHeaders()
        tableView.endUpdates()
        model.dataHasChanged = false
        log.viewCycle.debug("exiting from updateNSView")
    }
}

class ResultViewCoordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
    var parent: ResultView
    weak var tableView: TableViewWithPasteboard?
    
    init(_ parent: ResultView) {
        self.parent = parent
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
            log.viewCycle.debug("in populateColumnHeaders, columns changed, old columns: \( (tableView.tableColumns.map {$0.title}).joined(separator: ",") )")
            for c in tableView.tableColumns {
                tableView.removeTableColumn(c)
            }
            tableView.columnWidths.removeAll()
            log.viewCycle.debug("columns removed")
            for col in parent.model.columnLabels {
                let tabCol = NSTableColumn(identifier: .init(col))
                tabCol.title = col
                tabCol.minWidth = Constants.minColumnWidth
                tabCol.maxWidth = Constants.maxColumnWidth
                tabCol.resizingMask = .userResizingMask
                tabCol.sortDescriptorPrototype = NSSortDescriptor(key: col, ascending: true)
                tabCol.headerCell.attributedStringValue = NSAttributedString(string: col, attributes: [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: 12), NSAttributedString.Key.foregroundColor: NSColor.systemBlue])
                
                tableView.addTableColumn(tabCol)
                tableView.columnWidths.append(tabCol.width)
            }
            log.viewCycle.debug("columns added: \(tableView.tableColumns.count)")
        }
        // check auto width flag
        if parent.model.autoColWidth && tableView.numberOfRows > 0 { // base column width on data width
            for (idx, _) in tableView.tableColumns.enumerated() {
                sizeToFit(columnIndex: idx)
            }
            log.viewCycle.debug("new column widths: \(tableView.columnWidths)")
        } else if !parent.model.autoColWidth && tableView.numberOfRows > 0 { // base column width on header width
            for (idx, _) in tableView.tableColumns.enumerated() {
                tableView.tableColumns[idx].sizeToFit()
                tableView.tableColumns[idx].width += 20
            }
        }
        log.viewCycle.debug("exiting populateColumnHeaders")
    }
    
    func sizeToFit(columnIndex: Int) {
        guard let tableView = self.tableView else {
            return
        }
        if let view = tableView.view(atColumn: columnIndex, row: 0, makeIfNecessary: true) as? NSTableCellView {
            let colName = tableView.tableColumns[columnIndex].identifier.rawValue
            // get header width first
            tableView.tableColumns[columnIndex].sizeToFit()
            var colWidth = tableView.tableColumns[columnIndex].width + 20
            // now calculate optimal width based on data width
            for row in parent.model.rows {
                view.textField?.objectValue = row[colName]?.valueString
                // make data width capped at max column width
                let dataWidth = min((view.textField?.fittingSize ?? CGSize(width: 0.0, height: 0.0)).width, Constants.maxColumnWidth)
                colWidth = max(colWidth, dataWidth)
            }
            tableView.tableColumns[columnIndex].width = colWidth
        }
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        log.viewCycle.debug("numberOfRows: \(self.parent.model.rows.count)")
        return parent.model.rows.count
    }
    
    func makeTableCellView(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let text = NSTextField()
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.isBordered = false
        text.translatesAutoresizingMaskIntoConstraints = false
        text.font = NSFont(name: "Source Code Pro", size: NSFont.systemFontSize)
        text.placeholderString = "this is a text field"
        text.usesSingleLineMode = true
//        text.maximumNumberOfLines = 1
        text.cell?.wraps = false
//        text.preferredMaxLayoutWidth = 1200
        
        let cell = NSTableCellView()
        cell.textField = text
        cell.addSubview(text)
        cell.autoresizingMask = [.width, .height]
        cell.identifier = identifier
        
        // bind text field to cell's objectValue, which is auto-magically populated
        // by tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? (see below)
        cell.textField?.bind(.value , to: cell, withKeyPath: "objectValue", options: nil)
        
        cell.addConstraint(NSLayoutConstraint(item: text, attribute: .top, relatedBy: .equal, toItem: cell, attribute: .top, multiplier: 1, constant: 0))
        cell.addConstraint(NSLayoutConstraint(item: text, attribute: .leading, relatedBy: .equal, toItem: cell, attribute: .leading, multiplier: 1, constant: 0))
        
        return cell
    }
    
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        
        var cell: NSTableCellView
        let cellIdentifier = NSUserInterfaceItemIdentifier("cell")
        // find a cell object in cache
        if let existingCell = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) {
            cell = existingCell as! NSTableCellView
        } else {
            cell = makeTableCellView(identifier: cellIdentifier)
        }
        // set the value; this can be commented out if using bindings
        return cell
    }
    
//    func getColumnWidth(_ tableView: NSTableView, columnIndex: Int) -> CGFloat {
//        return (tableView as! TableViewWithPasteboard).columnWidths[columnIndex]
//    }
    
    func tableView(_ tableView: NSTableView, sizeToFitWidthOfColumn column: Int) -> CGFloat {
        return tableView.tableColumns[column].width
    }
    
//    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
//        print("selected row \(row)")
//        return true
//    }
    
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let sortDescriptor = tableView.sortDescriptors.first else { return }
        parent.model.sort(by: sortDescriptor.key, ascending: sortDescriptor.ascending)
        tableView.reloadData()
    }
    
    func getRowCSV(rowNumber: Int) -> String {
        // quotes around fields
        return (parent.model.rows[rowNumber].fields.map { "\"\($0.valueString)\"" }).joined(separator: ",")
    }
    
    func getSelectedRowsCSV() -> String {
        return tableView!.selectedRowIndexes.compactMap { getRowCSV(rowNumber: $0) }.joined(separator: "\n")
    }
    
    func getRowTSV(rowNumber: Int) -> String {
        // no quotes around fields
        return (parent.model.rows[rowNumber].fields.map { "\($0.valueString)" }).joined(separator: "\t")
    }
    
    func getSelectedRowsTSV() -> String {
        return tableView!.selectedRowIndexes.compactMap { getRowTSV(rowNumber: $0) }.joined(separator: "\n")
    }

    //        func tableView(_ tableView: NSTableView, toolTipFor cell: NSCell, rect: NSRectPointer, tableColumn: NSTableColumn?, row: Int, mouseLocation: NSPoint) -> String {
//            "tooltip"
//        }
    
//        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
//                let rowView = NSTableRowView()
//                rowView.isEmphasized = false
//                return rowView
//        }

//    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
//        25
//    }


//        @objc func tableViewDoubleClick(_ tableView: NSTableView) {
//            list.onDoubleClickRow(tableView.clickedRow)
    
//        }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row < parent.model.rows.count else { return "" }
        if tableColumn?.identifier.rawValue == "#" {
            return row+1
        } else {
            return parent.model.rows[row][tableColumn!.identifier.rawValue]?.valueString
        }
    }

}

