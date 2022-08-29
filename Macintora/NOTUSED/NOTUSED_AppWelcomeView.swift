import SwiftUI

struct AppWelcomeView: View {
    let buttonOpenDocumentTapped: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Logo()
                Spacer().frame(height: 10)
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")")
                    .foregroundColor(.secondary)
            }
            .frame(width: 500, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
            .frame(maxHeight: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/)
            .background(Color(NSColor.windowBackgroundColor))
            
            VStack(spacing: 32) {
                VStack(alignment: .leading) {
                    recentDocumentsList
                    
                    Spacer()
                    
                }
            }
            .frame(width: 300, alignment: .top)
            .frame(maxHeight: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/)
        }
    }
    
    private var recentDocumentsList: some View {
        List {
            ForEach(NSDocumentController.shared.recentDocumentURLs.prefix(5), id: \.self) { url in
                Button(action: { NSWorkspace.shared.open(url) }, label: {
                    let path = url.path.replacingOccurrences(of: "/Users/\(NSUserName())", with: "~", options: .anchored, range: nil)
                    HStack {
                        Image(systemName: "doc")
                            .font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                            Text(path)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }.padding([.top, .bottom], 4)
                }).buttonStyle(PlainButtonStyle())
            }
            
            Button(action: buttonOpenDocumentTapped) {
                Text("Open document")
            }
            .padding(.top, 10)
        }
    }
}

struct AppWelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        AppWelcomeView(buttonOpenDocumentTapped: {})
            .frame(width: 800, height: 460)
    }
}
