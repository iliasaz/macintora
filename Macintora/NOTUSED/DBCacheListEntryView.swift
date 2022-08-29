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
        VStack(alignment: .leading) {
            HStack {
                switch dbObject.type {
                    case "TABLE": Image(systemName: "tablecells").foregroundColor(Color.blue)
                    default: Image(systemName: "questionmark.square").foregroundColor(Color.blue)
                }
                
                Text(dbObject.name)
                    .lineLimit(1)
            }
        }
    }
}

//struct DBCacheListEntryView_Previews: PreviewProvider {
//    static var previews: some View {
//        DBCacheListEntryView()
//    }
//}
