import Foundation

struct MediaPage: Decodable {
    let results: [MovieInfo]
}

struct Genre: Decodable, Hashable {
    let id: Int
    let name: String
}

struct SeasonSummary: Decodable, Hashable, Identifiable {
    let seasonNumber: Int
    let episodeCount: Int?
    let name: String?

    var id: Int { seasonNumber }

    enum CodingKeys: String, CodingKey {
        case seasonNumber = "season_number"
        case episodeCount = "episode_count"
        case name
    }
}

/// `movie/{id}` or `tv/{id}` with `append_to_response=recommendations,external_ids`.
struct MediaDetails: Decodable {
    let runtime: Int?
    let numberOfSeasons: Int?
    let tagline: String?
    let genres: [Genre]?
    let seasons: [SeasonSummary]?
    let recommendations: MediaPage?

    /// Real seasons, in order; "Specials" (season 0) only if there's nothing else.
    var playableSeasons: [SeasonSummary] {
        let all = (seasons ?? []).sorted { $0.seasonNumber < $1.seasonNumber }
        let regular = all.filter { $0.seasonNumber > 0 && ($0.episodeCount ?? 0) > 0 }
        return regular.isEmpty ? all : regular
    }

    func recommended(as type: String?) -> [MovieInfo] {
        (recommendations?.results ?? [])
            .map { $0.withMediaType(type) }
            .filter { $0.posterPath != nil }
    }

    enum CodingKeys: String, CodingKey {
        case runtime, tagline, genres, seasons, recommendations
        case numberOfSeasons = "number_of_seasons"
    }
}

struct Episode: Decodable, Hashable, Identifiable {
    let episodeNumber: Int
    let name: String?
    let overview: String?
    let stillPath: String?
    let runtime: Int?
    let airDate: String?

    var id: Int { episodeNumber }
    var stillURL: URL? { TMDBImage.url(stillPath, size: "w780") }

    enum CodingKeys: String, CodingKey {
        case episodeNumber = "episode_number"
        case name, overview, runtime
        case stillPath = "still_path"
        case airDate = "air_date"
    }
}

struct SeasonDetails: Decodable {
    let episodes: [Episode]
}
