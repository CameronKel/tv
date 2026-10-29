import SwiftUI

struct ContentView: View {
    @StateObject private var playback = PlaybackViewModel()
    @StateObject private var history = WatchHistory.shared

    @State private var section: AppSection = .home
    /// Sections opened so far. Each loads on first visit, then stays alive.
    @State private var opened: Set<AppSection> = [.home]

    var body: some View {
        ZStack(alignment: .leading) {
            // Opened sections stay alive so each keeps its place; only the
            // selected one is shown and can take focus.
            ZStack {
                ForEach(AppSection.allCases.filter(opened.contains)) { item in
                    page(item)
                        .opacity(section == item ? 1 : 0)
                        .disabled(section != item)
                }
            }
            .padding(.leading, SideMenu.collapsedWidth)
            .focusSection()

            SideMenu(selection: $section)
        }
        .onChange(of: section) { opened.insert($0) }   // single-value signature for tvOS 16
        .environmentObject(playback)
        .environmentObject(history)
        .preferredColorScheme(.dark)
        .background(Color.black.ignoresSafeArea())
        .task { await SearchIndex.shared.warmUp() }
        .fullScreenCover(isPresented: $playback.isPresented, onDismiss: { playback.didDismiss() }) {
            PlayerScreen().environmentObject(playback)
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
