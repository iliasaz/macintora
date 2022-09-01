//
//  DBCacheBrowserMainView.swift
//
//  Created by Ilia on 1/1/22.
//

import SwiftUI
import CoreData

extension Animation {
    func `repeat`(while expression: Bool, autoreverses: Bool = true) -> Animation {
        if expression {
            return self.repeatForever(autoreverses: autoreverses)
        } else {
            return self
        }
    }
}


struct DBCacheBrowserMainView: View {
    @State var connDetails: ConnectionDetails
    @ObservedObject var cache: DBCacheVM
    @State private var reportDisplayed = false
    @EnvironmentObject var appSettings: AppSettings
    @AppStorage("searchLimit") private var searchLimit: Int = 20
    
    init(connDetails: ConnectionDetails) {
        _connDetails = State(initialValue: connDetails)
        self.cache = DBCacheVM(connDetails: connDetails)
    }
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 0) {
                headerView
                
                DBCacheListView(searchCriteria: cache.searchCriteria,
                          request: SectionedFetchRequest(fetchRequest: DBCacheObject.fetchRequest(limit: searchLimit), sectionIdentifier: \DBCacheObject.owner_, animation: .default))
                    .environment(\.managedObjectContext, cache.persistenceController.container.viewContext)
                    .environmentObject(cache)
                    .toolbar {
                        
                        ToolbarItemGroup(placement: .principal) {
                            Button {
                                cache.updateCache()
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .rotationEffect(Angle.degrees(cache.isReloading ? 360 : 0))
                                    .animation(.linear(duration: 2.0).repeat(while: cache.isReloading, autoreverses: false), value: cache.isReloading)
                            }
                            .disabled(cache.isReloading)
                            .help("Refresh Cache")

                            Button { reportDisplayed.toggle() } label: {
                                Label("Counts", systemImage: "sum")
                            }
                            .sheet(isPresented: $reportDisplayed) {
                                VStack {
                                    Text(cache.reportCacheCounts())
                                        .textSelection(.enabled)
                                        .lineLimit(20)
                                        .frame(width: 300.0, height: 200.0, alignment: .topLeading)
                                        .padding()
                                    Button { reportDisplayed.toggle() } label: { Text("Dismiss") }
                                    .padding()
                                }.padding()
                            }
                            .help("Show Cache counts")
                        }
                        
                        ToolbarItemGroup(placement: .confirmationAction) {
                            Button { cache.clearCache() } label: {
                                Label("Clear", systemImage: "trash")
                            }
                            .help("Clear Cache")
                        }
                }
                Spacer()
            }
            .padding(.vertical)
            .frame(minWidth: 300, idealWidth: 800, maxWidth: .infinity, minHeight: 600, idealHeight: 1000, maxHeight: .infinity)
        }
    }
    
    var headerView: some View {
        // db name and buttons
        VStack(alignment: .leading, spacing: 0) {
            Text("\(cache.connDetails.tns)").font(.headline) //.frame(alignment: .center)
                .padding(.horizontal)
                .padding(.vertical,3)
            // db details
            DisclosureGroup("DB Info") {
                VStack(alignment: .leading, spacing: 0) {
                    Text("DB version: \(cache.dbVersionFull ?? "(unknown)")")
                    Text("Cache updated: \(cache.lastUpdatedStr)")
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal)
        }
    }
}






//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        DBCacheBrowserMainView(cache: DBCacheVM(connDetails: ConnectionDetails(username: "apps", password: "apps", tns: "dmwoac", connectionRole: .regular)))
//    }
//}
