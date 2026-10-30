import SwiftUI

struct RowHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3)
            .fontWeight(.semibold)
            .padding(.horizontal, 20)
    }
}

/// A titled, horizontally scrolling row of posters.
struct MediaRow: View {
    let title: String
    let items: [MovieInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RowHeader(title: title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: UI.s(40)) {
                    ForEach(items) { PosterCard(media: $0) }
                }
                // Room for the focus lift, which the scroll view would clip.
                .padding(.horizontal, 20)
                .padding(.vertical, UI.s(36))
            }
        }
        .tvFocusSection()
    }
}

struct ContinueWatchingRow: View {
    let entries: [WatchEntry]
    let openDetails: (MovieInfo) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RowHeader(title: "Continue Watching")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: UI.s(40)) {
                    ForEach(entries) { ContinueCard(entry: $0, openDetails: openDetails) }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, UI.s(36))
            }
        }
        .tvFocusSection()
    }
}

/// The big featured title at the top of a tab.
struct HeroBanner: View {
    let media: MovieInfo

    @EnvironmentObject private var playback: PlaybackViewModel
    @EnvironmentObject private var history: WatchHistory

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: media.backdropURL)
                .frame(maxWidth: .infinity)
                .frame(height: UI.s(640))
                .clipped()
            LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.4), .clear],
                           startPoint: .bottomLeading, endPoint: .topTrailing)

            VStack(alignment: .leading, spacing: 18) {
                Text(media.displayName)
                    .font(.system(size: UI.s(64), weight: .bold))
                    .lineLimit(2)
                if let overview = media.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.callout)
                        .lineLimit(3)
                        .frame(maxWidth: UI.s(900), alignment: .leading)
                }
                HStack(spacing: 30) {
                    Button {
                        playback.play(media, target: history.playTarget(for: media))
                    } label: {
                        Label(history.playTarget(for: media).label, systemImage: "play.fill")
                    }
                    NavigationLink(value: media) {
                        Label("Details", systemImage: "info.circle")
                    }
                }
                .padding(.top, 10)
            }
            .padding(UI.s(50))
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 20)
        .tvFocusSection()
    }
}

extension View {
    /// Every tab pushes the same detail screen for a title.
    func mediaDestinations() -> some View {
        navigationDestination(for: MovieInfo.self) { MediaDetailView(media: $0) }
    }
}
