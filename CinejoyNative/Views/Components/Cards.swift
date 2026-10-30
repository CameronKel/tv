import SwiftUI
import UIKit

/// A TMDB image. Decoded images stay in memory, so a card that scrolls back
/// into view shows its picture at once instead of blanking and fading in again.
struct RemoteImage: View {
    let url: URL?

    @State private var loaded: (url: URL, image: UIImage)?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image = shown {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder
                if failed {
                    Image(systemName: "film").font(.largeTitle).foregroundStyle(.secondary)
                }
            }
        }
        .task(id: url) { await load() }
    }

    /// Never the previous URL's picture when the view is reused for another title.
    private var shown: UIImage? {
        guard let url else { return nil }
        if let loaded, loaded.url == url { return loaded.image }
        return ImageCache.shared[url]
    }

    private var placeholder: some View {
        Rectangle().fill(Color.white.opacity(0.08))
    }

    @MainActor
    private func load() async {
        failed = false
        guard let url else { failed = true; return }
        if let image = ImageCache.shared[url] {
            loaded = (url, image)
            return
        }
        guard let response = try? await URLSession.shared.data(from: url),
              let image = await UIImage(data: response.0)?.byPreparingForDisplay() else {
            if !Task.isCancelled { failed = true }
            return
        }
        ImageCache.shared[url] = image
        guard !Task.isCancelled else { return }
        withAnimation(.easeIn(duration: 0.2)) { loaded = (url, image) }
    }
}

/// Decoded images by URL. NSCache drops them under memory pressure.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 200 * 1024 * 1024
        return cache
    }()

    subscript(url: URL) -> UIImage? {
        get { cache.object(forKey: url as NSURL) }
        set {
            guard let image = newValue else { return cache.removeObject(forKey: url as NSURL) }
            let bytes = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            cache.setObject(image, forKey: url as NSURL, cost: bytes)
        }
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
    var width: CGFloat = UI.s(230)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: media) {
                RemoteImage(url: media.posterURL)
                    .frame(width: width, height: width * 1.5)
                    .clipped()
            }
            .accessibilityLabel(media.displayName)
            .cardButton()

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
                    .frame(width: UI.s(440), height: UI.s(248))
                    .clipped()
                    .overlay(alignment: .bottom) {
                        if entry.progress > 0 {
                            ProgressBar(value: entry.progress).padding(16)
                        }
                    }
            }
            .cardButton()
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
        .frame(width: UI.s(440), alignment: .leading)
    }

    private var subtitle: String {
        if entry.upNext, let label = entry.episodeLabel { return "Up next · \(label)" }
        let left = "\(entry.minutesLeft) min left"
        if let label = entry.episodeLabel { return "\(label) · \(left)" }
        return left
    }
}
