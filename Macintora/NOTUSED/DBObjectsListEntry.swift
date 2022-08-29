//
//  DBObjectsListEntry.swift
//  MacOra
//
//  Created by Ilia on 12/10/21.
//

import SwiftUI

struct DBObjectsListEntry: View {
    @ObservedObject var dbObject: DBCacheObject
    @Environment(\.managedObjectContext) private var managedObjectContext
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(dbObject.name).font(.title3)
                .lineLimit(1)
            HStack {
                Text(dbObject.owner).font(.caption)
                Text(dbObject.type).font(.caption)
            }
            HStack {
                Text(dbObject.lastDDLDate?.ISO8601Format() ?? "").font(.caption)
            }
        }
    }
}

