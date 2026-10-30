import Foundation

/// Where an episode's recap, intro and credits are, from TheIntroDB
/// (api.theintrodb.org: free, no key, crowd-sourced, keyed by TMDB id).
/// Popular shows are well covered; others have no submissions, and then the
/// player offers Next Episode near the end and no skip buttons.
struct EpisodeMarkers: Equatable {
    var recap: ClosedRange<Double>?
    var intro: ClosedRange<Double>?
    /// When the credits start, in seconds.
    var credits: Double?
}

enum TheIntroDB {
    static func markers(showID: Int, season: Int, episode: Int) async -> EpisodeMarkers? {
        var comps = URLComponents(string: "https://api.theintrodb.org/v2/media")!
        comps.queryItems = [
            URLQueryItem(name: "tmdb_id", value: String(showID)),
            URLQueryItem(name: "season", value: String(season)),
            URLQueryItem(name: "episode", value: String(episode)),
        ]
        guard let url = comps.url,
              let result = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10)),
              let response = try? JSONDecoder().decode(Response.self, from: result.0)
        else { return nil }

        let markers = EpisodeMarkers(
            recap: span(response.recap),
            intro: span(response.intro),
            credits: response.credits?.first?.startMs.map { Double($0) / 1000 }.flatMap { $0 > 60 ? $0 : nil }
        )
        return markers == EpisodeMarkers() ? nil : markers
    }

    /// A usable segment: a missing start means the episode's start, and
    /// anything under 5 s is a placeholder submission ("end": 0).
    private static func span(_ segments: [Segment]?) -> ClosedRange<Double>? {
        guard let segment = segments?.first, let end = segment.endMs else { return nil }
        let start = Double(segment.startMs ?? 0) / 1000
        let stop = Double(end) / 1000
        return stop - start >= 5 ? start...stop : nil
    }

    private struct Segment: Decodable {
        let startMs: Int?
        let endMs: Int?

        enum CodingKeys: String, CodingKey {
            case startMs = "start_ms"
            case endMs = "end_ms"
        }
    }

    private struct Response: Decodable {
        let recap: [Segment]?
        let intro: [Segment]?
        let credits: [Segment]?
    }
}
