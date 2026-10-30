import AVFoundation
import Combine
import SwiftUI

/// Resolves a title's stream, plays it full screen, and saves progress to
/// `WatchHistory` as it goes. One instance lives at the app root.
@MainActor
final class PlaybackViewModel: ObservableObject {
    @Published var isPresented = false {
        didSet {
            // Going away: stop the sound now, tear down once the cover is gone.
            if oldValue, !isPresented {
                isDismissing = true
                player?.pause()
            }
        }
    }
    @Published private(set) var player: AVPlayer?
    @Published var errorMessage: String?
    @Published private(set) var nowPlayingTitle = ""
    @Published private(set) var status = ""
    /// Buttons the player shows right now (Skip Intro, Next Episode).
    @Published private(set) var actions: [PlayerAction] = []

    struct Request {
        let media: MovieInfo
        let season: Int?
        let episode: Int?
        let episodeTitle: String?
        let id = UUID()
    }

    private(set) var request: Request?
    private(set) var nextEpisode: (season: Int, episode: Int)?
    /// Recap, intro and credits times for the current episode, if known.
    var markers: EpisodeMarkers?
    var actionObserver: Any?
    private var resumeAt: Double = 0
    private var hasStarted = false
    /// The current stream has actually played; failures after that are real errors.
    private var didPlay = false
    /// Sources not yet tried for this request, so a stream the player rejects
    /// can fall back to the next one.
    private var untriedSources: [String] = []
    private var currentSource: String?
    /// Why each source tried for this request didn't play, shown if they all fail.
    private var failures: [String] = []
    /// Sources whose streams the player rejected this launch; tried last from then on.
    private static var failedSources = Set<String>()
    /// Starting playback while the last player is still animating away would be
    /// ignored by SwiftUI, so it waits for `didDismiss()`.
    private var isDismissing = false
    private var presentWhenDismissed = false
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var loadTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private static let stallLimit: UInt64 = 20

    func setActions(_ new: [PlayerAction]) {
        actions = new
    }

    /// The full-screen cover finished closing.
    func didDismiss() {
        isDismissing = false
        if presentWhenDismissed {
            presentWhenDismissed = false
            isPresented = true
        } else if !isPresented {
            stop()
        }
    }

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
        status = "Finding a stream…"
        if isDismissing {
            presentWhenDismissed = true
        } else {
            isPresented = true
        }
        let all = NativeStreamResolver.sources
        untriedSources = all.filter { !Self.failedSources.contains($0) } + all.filter { Self.failedSources.contains($0) }

        let requestID = request?.id
        loadTask = Task { [weak self] in
            async let next = Self.lookUpNext(media: media, season: season, episode: episode)
            async let marks = Self.lookUpMarkers(media: media, season: season, episode: episode)
            await self?.resolveAndStart()
            let (upNext, markers) = await (next, marks)
            guard let self, self.request?.id == requestID else { return }
            self.nextEpisode = upNext
            self.markers = markers
        }
    }

    /// Resolves the request from the first untried source that has it, and plays it.
    private func resolveAndStart() async {
        guard let request else { return }
        do {
            let resolved = try await CinejoyAPI.shared.stream(
                for: request.media, season: request.season, episode: request.episode,
                sources: untriedSources)
            guard !Task.isCancelled else { return }
            untriedSources = Array(untriedSources.drop { $0 != resolved.source }.dropFirst())
            currentSource = resolved.source
            status = "Loading from \(resolved.source)…"
            start(resolved.url)
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = ([error.localizedDescription] + failures).joined(separator: "\n")
        }
    }

    /// The stream failed or stalled before it ever played: try the next source.
    private func fallBack(after item: AVPlayerItem) {
        guard player?.currentItem === item else { return }
        let reason = item.status == .failed ? Self.describe(item) : "The stream didn't start. Try again."
        if let currentSource {
            Self.failedSources.insert(currentSource)
            failures.append("\(currentSource): \(reason.components(separatedBy: "\n")[0])")
        }
        guard !untriedSources.isEmpty else {
            errorMessage = reason
            return
        }
        tearDownPlayer()
        status = "Trying another source…"
        loadTask = Task { [weak self] in await self?.resolveAndStart() }
    }

    /// Saves progress and tears the player down. Called when the player is dismissed.
    func stop() {
        loadTask?.cancel()
        loadTask = nil
        saveProgress()
        tearDownPlayer()
        request = nil
        nextEpisode = nil
        markers = nil
        untriedSources = []
        currentSource = nil
        failures = []
    }

    private func tearDownPlayer() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let actionObserver { player?.removeTimeObserver(actionObserver) }
        actionObserver = nil
        actions = []
        watchdog?.cancel()
        watchdog = nil
        cancellables.removeAll()
        player?.pause()
        player = nil
        hasStarted = false
        didPlay = false
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
                case .failed where !self.didPlay: self.fallBack(after: item)
                case .failed: self.errorMessage = Self.describe(item)
                default: break
                }
            }
            .store(in: &cancellables)

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] control in
                guard let self, control == .playing, !self.didPlay else { return }
                self.didPlay = true
                self.watchdog?.cancel()
            }
            .store(in: &cancellables)

        // A source whose stream never starts gets the same treatment as one that fails.
        watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.stallLimit * 1_000_000_000)
            guard !Task.isCancelled, let self, !self.didPlay, let item = self.player?.currentItem else { return }
            self.fallBack(after: item)
        }

        NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.saveProgress()
                self?.playNextEpisode()
            }
            .store(in: &cancellables)

        actionObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main
        ) { [weak self] time in
            Task { @MainActor in self?.updateActions(at: time.seconds) }
        }

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

    func saveProgress() {
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

    private static func lookUpMarkers(media: MovieInfo, season: Int?, episode: Int?) async -> EpisodeMarkers? {
        guard media.isTV, let season, let episode else { return nil }
        return await TheIntroDB.markers(showID: media.tmdbID, season: season, episode: episode)
    }

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
