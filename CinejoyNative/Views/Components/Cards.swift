import SwiftUI

struct RemoteImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.25))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                placeholder.overlay(Image(systemName: "film").font(.largeTitle).foregroundStyle(.secondary))
            default:
                placeholder
            }
        }
    }

    private var placeholder: some View {
        Rectangle().fill(Color.white.opacity(0.08))
    }
}

struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.3))
                Capsule().fill(Color.white).frame(width: geo.size.width * value)
            }
        }
        .frame(height: 6)
    }
}

/// A focusable poster that opens the title's detail screen, with its name below.
struct PosterCard: View {
    let media: MovieInfo
    var width: CGFloat = 230

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: media) {
                RemoteImage(url: media.posterURL)
                    .frame(width: width, height: width * 1.5)
                    .clipped()
            }
            .buttonStyle(.card)

            Text(media.displayName)
                .font(.caption)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
    }
}

/// A landscape card that resumes playback straight away. Long-press for more.
struct ContinueCard: View {
    let entry: WatchEntry
    let openDetails: (MovieInfo) -> Void

    @EnvironmentObject private var playback: PlaybackViewModel
    @EnvironmentObject private var history: WatchHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                playback.play(entry.media, target: history.playTarget(for: entry.media))
            } label: {
                RemoteImage(url: entry.media.backdropURL ?? entry.media.posterURL)
                    .frame(width: 440, height: 248)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        if entry.progress > 0 {
                            ProgressBar(value: entry.progress).padding(16)
                        }
                    }
            }
            .buttonStyle(.card)
            .contextMenu {
                Button { openDetails(entry.media) } label: {
                    Label("Go to Details", systemImage: "info.circle")
                }
                Button(role: .destructive) { history.remove(entry.media) } label: {
                    Label("Remove from Continue Watching", systemImage: "xmark")
                }
            }

            Text(entry.media.displayName).font(.headline).lineLimit(1)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 440, alignment: .leading)
    }

    private var subtitle: String {
        if entry.upNext, let label = entry.episodeLabel { return "Up next · \(label)" }
        let left = "\(entry.minutesLeft) min left"
        if let label = entry.episodeLabel { return "\(label) · \(left)" }
        return left
    }
}
