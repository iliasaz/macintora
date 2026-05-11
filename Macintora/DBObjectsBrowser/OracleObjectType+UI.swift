//
//  OracleObjectType+UI.swift
//  Macintora
//
//  Per-type color + SF Symbol presentation derived from the v2 design tokens.
//  Centralising these here avoids the duplicated switch statements that used
//  to live in DBCacheListEntryView and DBDetailViewHeaderImage.
//

import SwiftUI

extension OracleObjectType {
    /// Human label used in the detail header strip.
    var label: String {
        switch self {
        case .table:     "Table"
        case .view:      "View"
        case .index:     "Index"
        case .type:      "Type"
        case .package:   "Package"
        case .procedure: "Procedure"
        case .function:  "Function"
        case .trigger:   "Trigger"
        case .unknown:   "Object"
        }
    }

    var symbolName: String {
        switch self {
        case .table:     "tablecells"
        case .view:      "tablecells.badge.ellipsis"
        case .index:     "list.bullet.indent"
        case .type:      "shippingbox"
        case .package:   "ellipsis.curlybraces"
        case .procedure: "curlybraces"
        case .function:  "f.cursive"
        case .trigger:   "bolt"
        case .unknown:   "questionmark.square"
        }
    }

    /// Tint derived from the v2 design tokens (--o-* family). Each type gets a
    /// distinguishable hue so a glance at the sidebar tells you what you're
    /// looking at without reading the name.
    var tint: Color {
        switch self {
        case .table:     Color(red: 0x29/255, green: 0x66/255, blue: 0xC9/255)
        case .view:      Color(red: 0x71/255, green: 0x48/255, blue: 0xC9/255)
        case .index:     Color(red: 0x12/255, green: 0x8A/255, blue: 0xA1/255)
        case .package:   Color(red: 0xC9/255, green: 0x6A/255, blue: 0x21/255)
        case .procedure: Color(red: 0xC9/255, green: 0x3A/255, blue: 0x78/255)
        case .function:  Color(red: 0x2D/255, green: 0x94/255, blue: 0x60/255)
        case .trigger:   Color(red: 0xC9/255, green: 0x3A/255, blue: 0x2E/255)
        case .type:      Color(red: 0x19/255, green: 0x86/255, blue: 0x82/255)
        case .unknown:   .secondary
        }
    }

    /// Stable order used by the sidebar type rail.
    static let displayOrder: [OracleObjectType] = [
        .table, .view, .index, .package, .procedure, .function, .trigger, .type
    ]
}
