import AVFoundation
import Combine
import SwiftUI

/// Resolves a title's stream, plays it full screen, and saves progress to
/// `WatchHistory` as it goes. One instance lives at the app root.
@MainActor
final class PlaybackViewModel: ObservableObject {
    @Published var isPresented = false
    @Published private(set) var player: AVPlayer?
    @Published var errorMessage: String?
    @Published private(set) var nowPlayingTitle = ""

    private struct Request {
        let media: MovieInfo
        let season: Int?
        let episode: Int?
        let episodeTitle: String?
    }

    private var request: Request?
    private var nextEpisode: (season: Int, episode: Int)?
    private var resumeAt: Double = 0
    private var hasStarted = false
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var loadTask: Task<Void, Never>?

    func play(_ media: MovieInfo, target: PlayTarget) {
        play(media, season: target.season, episode: target.episode,
             episodeTitle: target.episodeTitle, resumeAt: target.resumeAt)
    }

    func play(_ media: MovieInfo, season: Int? = nil, episode: Int? = nil,
              episodeTitle: String? = nil, resumeAt: Double = 0) {
        stop()
        request = Request(media: media, season: season, episode: episode, episodeTitle: episodeTitle)
        self.resumeAt = resumeAt
        nowPlayingTitle = Self.title(media: media, season: season, episode: episode, episodeTitle: episodeTitle)
        errorMessage = nil
        isPresented = true

        loadTask = Task { [weak self] in
            do {
                async let next = Self.lookUpNext(media: media, season: season, episode: episode)
                let url = try await CinejoyAPI.shared.streamURL(for: media, season: season, episode: episode)
                let upNext = await next
                guard let self, !Task.isCancelled else { return }
                self.nextEpisode = upNext
                self.start(url)
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// Saves progress and tears the player down. Called when the player is dismissed.
    func stop() {
        loadTask?.cancel()
        loadTask = nil
        saveProgress()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        cancellables.removeAll()
        player?.pause()
        player = nil
        request = nil
        nextEpisode = nil
        hasStarted = false
    }

    // MARK: - Playback

    private func start(_ url: URL) {
        let item = AVPlayerItem(asset: HLSResourceLoader.asset(for: url))
        item.externalMetadata = metadata()
        let player = AVPlayer(playerItem: item)

        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] status in
                guard let self, let item else { return }
                switch status {
                case .readyToPlay: self.beginIfNeeded()
                case .failed: self.errorMessage = Self.describe(item)
                default: break
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.saveProgress() }
            .store(in: &cancellables)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 10, preferredTimescale: 1), queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.saveProgress() }
        }

        self.player = player
        if resumeAt <= 0 {
            hasStarted = true
            player.play()
        }
    }

    /// Seeks to the resume point once the item can seek, then plays.
    private func beginIfNeeded() {
        guard !hasStarted, let player else { return }
        hasStarted = true
        player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600))
        player.play()
    }

    private func saveProgress() {
        guard let request, let item = player?.currentItem else { return }
        let position = item.currentTime().seconds
        let duration = item.duration.seconds
        guard position.isFinite, duration.isFinite, duration > 0, position > 0 else { return }

        let history = WatchHistory.shared
        history.record(request.media, season: request.season, episode: request.episode,
                       episodeTitle: request.episodeTitle, position: position, duration: duration)
        if position / duration >= WatchEntry.finishedThreshold, let next = nextEpisode {
            history.recordUpNext(request.media, season: next.season, episode: next.episode)
        }
    }

    // MARK: - Helpers

    private static func lookUpNext(media: MovieInfo, season: Int?, episode: Int?) async -> (season: Int, episode: Int)? {
        guard media.isTV, let season, let episode else { return nil }
        return await CinejoyAPI.shared.nextEpisode(showID: media.tmdbID, season: season, episode: episode)
    }

    private static func title(media: MovieInfo, season: Int?, episode: Int?, episodeTitle: String?) -> String {
        guard let season, let episode else { return media.displayName }
        var parts = [media.displayName, "S\(season) E\(episode)"]
        if let episodeTitle, !episodeTitle.isEmpty { parts.append(episodeTitle) }
        return parts.joined(separator: " · ")
    }

    /// Title and synopsis for the player's info panel.
    private func metadata() -> [AVMetadataItem] {
        let title = AVMutableMetadataItem()
        title.identifier = .commonIdentifierTitle
        title.value = nowPlayingTitle as NSString
        title.extendedLanguageTag = "und"
        let summary = AVMutableMetadataItem()
        summary.identifier = .commonIdentifierDescription
        summary.value = (request?.media.overview ?? "") as NSString
        summary.extendedLanguageTag = "und"
        return [title, summary]
    }

    private static func describe(_ item: AVPlayerItem) -> String {
        let err = item.error as NSError?
        var parts = ["Stream failed: \(err?.localizedDescription ?? "unknown error")"]
        if let err {
            parts.append("code \(err.domain) \(err.code)")
            if let under = err.userInfo[NSUnderlyingErrorKey] as? NSError {
                parts.append("underlying \(under.domain) \(under.code): \(under.localizedDescription)")
            }
        }
        if let event = item.errorLog()?.events.last {
            parts.append("http \(event.errorStatusCode) \(event.errorComment ?? "")")
        }
        return parts.joined(separator: "\n")
    }
}
