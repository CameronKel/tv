import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            BrowseView()
                .tabItem { Label("Browse", systemImage: "square.grid.2x2") }
        }
    }
}
