import SwiftUI

struct ContentView: View {
    @StateObject private var playback = PlaybackViewModel()
    @StateObject private var history = WatchHistory.shared

    @State private var section: AppSection = .home

    var body: some View {
        sections
            .environmentObject(playback)
            .environmentObject(history)
            .preferredColorScheme(.dark)
            .task { await SearchIndex.shared.warmUp() }
            .fullScreenCover(isPresented: $playback.isPresented, onDismiss: { playback.didDismiss() }) {
                PlayerScreen().environmentObject(playback)
            }
    }

    /// Apple TV: the system sidebar (tvOS 18+). iPad: the floating tab bar at
    /// the top (iPadOS 18; its sidebar style left a blank column covering the
    /// page in landscape). Older systems: plain tabs.
    @ViewBuilder
    private var sections: some View {
        if #available(tvOS 18.0, iOS 18.0, *) {
            TabView(selection: $section) {
                ForEach(AppSection.allCases) { item in
                    Tab(item.title, systemImage: item.icon, value: item) { page(item) }
                }
            }
            #if os(tvOS)
            .tabViewStyle(.sidebarAdaptable)
            #endif
        } else {
            TabView(selection: $section) {
                ForEach(AppSection.allCases) { item in
                    page(item)
                        .tabItem { Label(item.title, systemImage: item.icon) }
                        .tag(item)
                }
            }
        }
    }

    @ViewBuilder
    private func page(_ item: AppSection) -> some View {
        switch item {
        case .home: HomeView()
        case .movies: BrowseView(specs: Catalog.movies)
        case .tv: BrowseView(specs: Catalog.tv)
        case .search: SearchView()
        }
    }
}
