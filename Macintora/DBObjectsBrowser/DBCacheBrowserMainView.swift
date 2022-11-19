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
    
    init(connDetails: ConnectionDetails, preview: Bool = false, selectedObjectName: String? = nil) {
        _connDetails = State(initialValue: connDetails)
        if preview {
            self.cache = DBCacheVM.init(preview: true)
        } else {
            self.cache = DBCacheVM(connDetails: connDetails, selectedObjectName: selectedObjectName)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 0) {
                headerView
                
                DBCacheListView(searchCriteria: cache.searchCriteria,
                                request: SectionedFetchRequest(fetchRequest: DBCacheObject.fetchRequest(limit: searchLimit, predicate: cache.searchCriteria.predicate), sectionIdentifier: \DBCacheObject.owner_, animation: .default))
                    .environment(\.managedObjectContext, cache.persistenceController.container.viewContext)
                    .environmentObject(cache)

                Spacer()
            }
            .padding(.vertical)
            .frame(minWidth: 300, idealWidth: 800, maxWidth: .infinity, minHeight: 600, idealHeight: 1000, maxHeight: .infinity)
        }
        .toolbar {
            
            ToolbarItemGroup(placement: .principal) {
                Menu {
                    Button(cache.isReloading ? "Working..." : "Incremental Refresh") {
                        guard !cache.isReloading else { return }
                        cache.updateCache()
                    }
                    
                    Button(cache.isReloading ? "Working..." : "Full Refresh (No Vacuum)") {
                        guard !cache.isReloading else { return }
                        cache.updateCache(ignoreLastUpdate: true)
                    }
                    
                    Button(cache.isReloading ? "Working..." : "Full Refresh + Vacuum") {
                        guard !cache.isReloading else { return }
                        cache.updateCache(ignoreLastUpdate: true, withCleanup: true)
                    }

                    Button(cache.isReloading ? "Working..." : "Vacuum Only") {
                        guard !cache.isReloading else { return }
                        cache.updateCache(cleanupOnly: true)
                    }

                } label: {
//                                Image(systemName: "arrow.triangle.2.circlepath")
                    Label(cache.isReloading ? "Working..." : "Refresh", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Refresh Cache")

                    // animation not working in menu
//                                    .rotationEffect(Angle.degrees(cache.isReloading ? 360 : 0))
//                                    .animation(.linear(duration: 2.0).repeat(while: cache.isReloading, autoreverses: false), value: cache.isReloading)
                

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
            
            ToolbarItemGroup(placement: .status) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .rotationEffect(Angle.degrees(cache.isReloading ? 360 : 0))
                    .animation(.linear(duration: 2.0).repeat(while: cache.isReloading, autoreverses: false), value: cache.isReloading)
                    .foregroundColor(cache.isReloading ? .red : .green)
            }
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






struct DBCacheBrowserMainView_Previews: PreviewProvider {
    static var previews: some View {
        DBCacheBrowserMainView(connDetails: ConnectionDetails(username: "apps", password: "apps", tns: "preview", connectionRole: .regular), preview: true)
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
            .frame(width: 800, height: 800)
    }
}
