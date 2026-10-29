import SwiftUI

struct HomeView: View {
    @StateObject private var browse = BrowseViewModel(specs: Catalog.home)
    @StateObject private var recommendations = RecommendationsModel()
    @EnvironmentObject private var history: WatchHistory
    @State private var path: [MovieInfo] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    if let hero = browse.hero {
                        HeroBanner(media: hero)
                    }
                    if !history.continueWatching.isEmpty {
                        ContinueWatchingRow(entries: history.continueWatching) { path.append($0) }
                    }
                    if !history.recentlyWatched.isEmpty {
                        MediaRow(title: "Recently Watched", items: history.recentlyWatched.map(\.media))
                    }
                    if !history.myList.isEmpty {
                        MediaRow(title: "My List", items: history.myList)
                    }
                    ForEach(recommendations.shelves) { MediaRow(title: $0.title, items: $0.items) }
                    ForEach(browse.shelves) { MediaRow(title: $0.title, items: $0.items) }

                    LoadingState(isEmpty: browse.shelves.isEmpty, error: browse.errorMessage) {
                        Task { await browse.load() }
                    }
                }
                .padding(.vertical, 40)
            }
            .task { await browse.load() }
            .task(id: history.entries.prefix(2).map(\.id)) {
                await recommendations.load(from: history.entries)
            }
            .mediaDestinations()
        }
    }
}

/// A Movies or TV Shows tab: a featured title, then rows from the catalog.
struct BrowseView: View {
    @StateObject private var browse: BrowseViewModel

    init(specs: [ShelfSpec]) {
        _browse = StateObject(wrappedValue: BrowseViewModel(specs: specs))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    if let hero = browse.hero {
                        HeroBanner(media: hero)
                    }
                    ForEach(browse.shelves) { MediaRow(title: $0.title, items: $0.items) }

                    LoadingState(isEmpty: browse.shelves.isEmpty, error: browse.errorMessage) {
                        Task { await browse.load() }
                    }
                }
                .padding(.vertical, 40)
            }
            .task { await browse.load() }
            .mediaDestinations()
        }
    }
}

/// A spinner while rows load, or the error with a retry button.
struct LoadingState: View {
    let isEmpty: Bool
    let error: String?
    let retry: () -> Void

    var body: some View {
        if let error {
            VStack(spacing: 24) {
                Text(error).foregroundStyle(.secondary)
                Button("Try Again", action: retry)
            }
            .frame(maxWidth: .infinity)
            .padding(80)
        } else if isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(120)
        }
    }
}
