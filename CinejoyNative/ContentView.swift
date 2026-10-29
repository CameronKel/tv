import SwiftUI

struct ContentView: View {
    @StateObject private var playback = PlaybackViewModel()
    @StateObject private var history = WatchHistory.shared

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
            BrowseView(specs: Catalog.movies)
                .tabItem { Label("Movies", systemImage: "film") }
            BrowseView(specs: Catalog.tv)
                .tabItem { Label("TV Shows", systemImage: "tv") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
        .environmentObject(playback)
        .environmentObject(history)
        .preferredColorScheme(.dark)
        .task { await SearchIndex.shared.warmUp() }
        .fullScreenCover(isPresented: $playback.isPresented, onDismiss: { playback.stop() }) {
            PlayerScreen().environmentObject(playback)
        }
    }
}
