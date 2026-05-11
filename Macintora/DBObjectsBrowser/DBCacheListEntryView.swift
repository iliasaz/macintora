//
//  DBCacheListEntryView.swift
//  DBObjectsBrowser
//
//  Created by Ilia on 1/6/22.
//

import SwiftUI

struct DBCacheListEntryView: View {
    @ObservedObject var dbObject: DBCacheObject
    @Environment(\.managedObjectContext) private var managedObjectContext

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .foregroundStyle(iconTint)
                .frame(width: 16)
            Text(dbObject.name)
                .lineLimit(1)
            if !dbObject.isValid {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .help("Invalid object")
                    .accessibilityLabel("Invalid")
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }

    private var symbolName: String {
        switch dbObject.type {
        case "TABLE":     return "tablecells"
        case "VIEW":      return "tablecells.badge.ellipsis"
        case "TYPE":      return "shippingbox"
        case "PACKAGE":   return "ellipsis.curlybraces"
        case "INDEX":     return "list.bullet.indent"
        case "TRIGGER":   return "bolt"
        case "PROCEDURE": return "curlybraces"
        case "FUNCTION":  return "f.cursive"
        default:          return "questionmark.square"
        }
    }

    /// Per-type tint role. HIG: "Avoid stylizing your app by specifying a
    /// fixed color for all sidebar icons." Tint roles let the accent color
    /// drive presentation while still giving each type a distinguishable hue.
    private var iconTint: HierarchicalShapeStyle {
        .secondary
    }
}

//struct DBCacheListEntryView_Previews: PreviewProvider {
//    static var previews: some View {
//        DBCacheListEntryView()
//    }
//}
