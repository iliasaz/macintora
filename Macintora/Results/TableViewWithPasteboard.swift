//
//  TableViewWithPasteboard.swift
//  Macintora
//
//  Created by Ilia Sazonov on 7/1/22.
//

import Foundation
import AppKit

class TableViewWithPasteboard: NSTableView, NSMenuItemValidation {

    // this is needed to teach our table view respond to Cmd-C
    override var acceptsFirstResponder: Bool { true }
    var columnWidths = [CGFloat]()
    var copyFormatter: (() -> String)?
    
    // Cmd-C reponder
    @objc func copy(_ sender: AnyObject?) {
        guard let copyFormatter = copyFormatter else { return }
//        let coordinator = self.delegate as! ResultViewCoordinator
        // get selected rows, for each row get CSV representation
//        let textToDisplayInPasteboard = coordinator.getSelectedRowsTSV()
        let textToDisplayInPasteboard = copyFormatter()
        // put them into a pasteboard
        let pasteBoard = NSPasteboard.general
        pasteBoard.clearContents()
        pasteBoard.setString(textToDisplayInPasteboard, forType:NSPasteboard.PasteboardType.string)
    }

//        @IBAction func paste(_ sender: AnyObject?) {
//            // add your logic to paste rows from the clipboard
//        }

    // this is needed to teach our table view respond to Cmd-C
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.identifier {
        case NSUserInterfaceItemIdentifier("copy:"):
            // enable Copy if at least one row is selected
            return numberOfSelectedRows > 0
//            case NSUserInterfaceItemIdentifier("paste:"):
            // enable Paste if clipboard contains data that is pasteable
            // (add your logic to read the clipboard
            // and conditionally enable Paste here)
        case NSUserInterfaceItemIdentifier("selectAll:"):
                return numberOfSelectedRows > 0
        default:
            return false
        }
    }
}
