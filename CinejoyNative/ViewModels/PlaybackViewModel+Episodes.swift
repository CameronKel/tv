import AVFoundation

/// The show controls on top of plain playback: Skip Recap / Skip Intro while
/// those play, Next Episode once the credits start (or the last 40 s when
/// TheIntroDB has no times), and playing on into the next episode.
extension PlaybackViewModel {
    enum PlayerAction: Equatable {
        case skipRecap(to: Double)
        case skipIntro(to: Double)
        case nextEpisode

        var icon: String {
            switch self {
            case .skipRecap, .skipIntro: return "forward.fill"
            case .nextEpisode: return "forward.end.fill"
            }
        }

        var title: String {
            switch self {
            case .skipRecap: return "Skip Recap"
            case .skipIntro: return "Skip Intro"
            case .nextEpisode: return "Next Episode"
            }
        }
    }

    private static let fallbackCreditsLength: Double = 40

    /// The show playing, for the Episodes tab; nil for movies.
    var currentShow: MovieInfo? {
        request.flatMap { $0.media.isTV ? $0.media : nil }
    }

    var currentSeason: Int? { request?.season }
    var currentEpisode: Int? { request?.episode }

    func perform(_ action: PlayerAction) {
        switch action {
        case .skipRecap(let end), .skipIntro(let end):
            player?.seek(to: CMTime(seconds: end, preferredTimescale: 600))
            updateActions(at: end)
        case .nextEpisode:
            playNextEpisode()
        }
    }

    /// Marks the current episode watched and starts the next one, if there is one.
    func playNextEpisode() {
        guard let request, let next = nextEpisode else { return }
        let duration = player?.currentItem?.duration.seconds ?? 0
        stop()
        if duration.isFinite, duration > 0 {
            WatchHistory.shared.record(request.media, season: request.season, episode: request.episode,
                                       episodeTitle: request.episodeTitle, position: duration, duration: duration)
        }
        play(request.media, season: next.season, episode: next.episode)
    }

    /// Works out which buttons apply at `time` (seconds into the episode).
    func updateActions(at time: Double) {
        guard currentShow != nil, time.isFinite else {
            if !actions.isEmpty { setActions([]) }
            return
        }
        var now: [PlayerAction] = []
        if let recap = markers?.recap, recap.contains(time), time < recap.upperBound - 2 {
            now.append(.skipRecap(to: recap.upperBound))
        }
        if let intro = markers?.intro, intro.contains(time), time < intro.upperBound - 2 {
            now.append(.skipIntro(to: intro.upperBound))
        }
        let duration = player?.currentItem?.duration.seconds ?? .nan
        if nextEpisode != nil, duration.isFinite, duration > 0 {
            let credits = markers?.credits.flatMap { $0 < duration ? $0 : nil }
                ?? duration - Self.fallbackCreditsLength
            if time >= credits { now.append(.nextEpisode) }
        }
        if now != actions { setActions(now) }
    }
}
