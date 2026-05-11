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
    var showPinIndicator: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: type.symbolName)
                .foregroundStyle(type.tint)
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
            if showPinIndicator {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Pinned")
            }
        }
        .contentShape(.rect)
    }

    private var type: OracleObjectType {
        OracleObjectType(rawValue: dbObject.type) ?? .unknown
    }
}
