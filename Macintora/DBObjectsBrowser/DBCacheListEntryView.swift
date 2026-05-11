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
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if showPinIndicator {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Pinned")
            }
            if !dbObject.isValid {
                StatusPill(text: "INVALID", role: .invalid)
            }
        }
        .contentShape(.rect)
    }

    private var type: OracleObjectType {
        OracleObjectType(rawValue: dbObject.type) ?? .unknown
    }
}

/// Compact right-aligned status badge used in the sidebar object list and the
/// detail header. Matches the v2 design's "INVALID" pill.
struct StatusPill: View {
    enum Role { case invalid, warn, ok }
    let text: String
    var role: Role = .invalid

    private var color: Color {
        switch role {
        case .invalid: .red
        case .warn:    .orange
        case .ok:      .green
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .kerning(0.3)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.16)))
            .accessibilityLabel(text)
    }
}
