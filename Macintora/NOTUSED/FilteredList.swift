//
//  FilteredList.swift
//  MacOra
//
//  Created by Ilia on 11/30/21.
//

import SwiftUI
import CoreData

struct FilteredList<T: NSManagedObject, Content: View>: View {
//    @FetchRequest private var items: FetchedResults<T>
//    @Environment(\.managedObjectContext) var context
    private var items: FetchedResults<T>
    let content: (T) -> Content
    
    var body: some View {
        List(items, id: \.self) { item in
            content(item)
        }
        .id(UUID())
    }
    
//    init(fetchParams: (NSPredicate, [NSSortDescriptor]), @ViewBuilder content: @escaping (T) -> Content) {
//        log.debug("in FilterList.init, params: \(fetchParams)")
//        _items = FetchRequest<T>(sortDescriptors: fetchParams.1, predicate: fetchParams.0)
//        self.content = content
//    }
    
    init(fetchResults: FetchedResults<T>, @ViewBuilder content: @escaping (T) -> Content) {
//        log.debug("in FilterList.init, fetchRequest: \(fetchRequest)")
        items = fetchResults
        self.content = content
    }
}

