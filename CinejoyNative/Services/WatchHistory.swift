import Foundation

/// Where a title was left: one per movie or show (a show's latest episode).
struct WatchEntry: Codable, Identifiable, Equatable {
    static let finishedThreshold = 0.93

    var media: MovieInfo
    var season: Int?
    var episode: Int?
    var episodeTitle: String?
    var position: Double
    var duration: Double
    /// The show's previous episode was finished; this one hasn't started.
    var upNext: Bool
    var updatedAt: Date

    var id: String { media.id }
    var progress: Double { duration > 0 ? min(max(position / duration, 0), 1) : 0 }
    var isFinished: Bool { !upNext && progress >= Self.finishedThreshold }
    var minutesLeft: Int { max(Int((duration - position) / 60), 1) }

    var episodeLabel: String? {
        guard let season, let episode else { return nil }
        return "S\(season) E\(episode)"
    }
}

struct EpisodeMark: Codable, Equatable {
    var position: Double
    var duration: Double
    var progress: Double { duration > 0 ? min(max(position / duration, 0), 1) : 0 }
}

/// What the Play button should do for a title.
struct PlayTarget {
    var season: Int?
    var episode: Int?
    var episodeTitle: String?
    var resumeAt: Double
    var label: String
}

/// Watch progress and My List, kept on the device (there's one user).
@MainActor
final class WatchHistory: ObservableObject {
    static let shared = WatchHistory()

    @Published private(set) var entries: [WatchEntry] = []
    @Published private(set) var episodeMarks: [String: EpisodeMark] = [:]
    @Published private(set) var myList: [MovieInfo] = []

    private let defaults = UserDefaults.standard
    private enum Key {
        static let entries = "watch.entries.v1"
        static let episodes = "watch.episodes.v1"
        static let myList = "watch.mylist.v1"
    }

    private init() {
        entries = load(Key.entries) ?? []
        episodeMarks = load(Key.episodes) ?? [:]
        myList = load(Key.myList) ?? []
    }

    var continueWatching: [WatchEntry] {
        entries.filter { $0.upNext || (!$0.isFinished && $0.position >= 60) }
    }

    var recentlyWatched: [WatchEntry] { Array(entries.prefix(20)) }

    func entry(for media: MovieInfo) -> WatchEntry? {
        entries.first { $0.id == media.id }
    }

    func mark(showID: Int, season: Int, episode: Int) -> EpisodeMark? {
        episodeMarks[Self.key(showID, season, episode)]
    }

    func record(_ media: MovieInfo, season: Int?, episode: Int?, episodeTitle: String?,
                position: Double, duration: Double) {
        guard duration > 0 else { return }
        upsert(WatchEntry(media: media, season: season, episode: episode, episodeTitle: episodeTitle,
                          position: position, duration: duration, upNext: false, updatedAt: Date()))
        if let season, let episode {
            episodeMarks[Self.key(media.tmdbID, season, episode)] =
                EpisodeMark(position: position, duration: duration)
            store(episodeMarks, Key.episodes)
        }
        store(entries, Key.entries)
    }

    func recordUpNext(_ media: MovieInfo, season: Int, episode: Int) {
        upsert(WatchEntry(media: media, season: season, episode: episode, episodeTitle: nil,
                          position: 0, duration: 0, upNext: true, updatedAt: Date()))
        store(entries, Key.entries)
    }

    func remove(_ media: MovieInfo) {
        entries.removeAll { $0.id == media.id }
        store(entries, Key.entries)
    }

    func isInMyList(_ media: MovieInfo) -> Bool {
        myList.contains { $0.id == media.id }
    }

    func toggleMyList(_ media: MovieInfo) {
        if isInMyList(media) {
            myList.removeAll { $0.id == media.id }
        } else {
            myList.insert(media, at: 0)
        }
        store(myList, Key.myList)
    }

    func playTarget(for media: MovieInfo, firstSeason: Int = 1) -> PlayTarget {
        let entry = self.entry(for: media)
        if media.isTV {
            if let entry, let season = entry.season, let episode = entry.episode, !entry.isFinished {
                if entry.upNext || entry.position < 60 {
                    return PlayTarget(season: season, episode: episode, episodeTitle: entry.episodeTitle,
                                      resumeAt: 0, label: "Play S\(season) E\(episode)")
                }
                return PlayTarget(season: season, episode: episode, episodeTitle: entry.episodeTitle,
                                  resumeAt: entry.position, label: "Resume S\(season) E\(episode)")
            }
            return PlayTarget(season: firstSeason, episode: 1, episodeTitle: nil,
                              resumeAt: 0, label: "Play S\(firstSeason) E1")
        }
        if let entry, !entry.isFinished, entry.position >= 60 {
            return PlayTarget(resumeAt: entry.position, label: "Resume")
        }
        return PlayTarget(resumeAt: 0, label: "Play")
    }

    // MARK: - Storage

    private func upsert(_ entry: WatchEntry) {
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
    }

    private static func key(_ showID: Int, _ season: Int, _ episode: Int) -> String {
        "\(showID)-s\(season)e\(episode)"
    }

    private func load<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func store<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}
