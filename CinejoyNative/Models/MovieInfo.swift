import Foundation

/// A movie or TV show as TMDB lists it. Also what watch history and My List store.
struct MovieInfo: Identifiable, Hashable, Codable {
    var tmdbID: Int
    var title: String?
    var name: String?
    var overview: String?
    var posterPath: String?
    var backdropPath: String?
    var releaseDate: String?
    var firstAirDate: String?
    var mediaType: String?
    var voteAverage: Double?
    var popularity: Double?

    /// Movies and shows share TMDB id space, so the type is part of the id.
    var id: String { "\(mediaType ?? "movie")-\(tmdbID)" }

    var isTV: Bool { mediaType == "tv" }

    var displayName: String { title ?? name ?? "Unknown" }

    var year: String? {
        guard let date = releaseDate ?? firstAirDate, date.count >= 4 else { return nil }
        return String(date.prefix(4))
    }

    var displayTitle: String {
        if let year { return "\(displayName) (\(year))" }
        return displayName
    }

    var posterURL: URL? { TMDBImage.url(posterPath, size: "w342") }
    var largePosterURL: URL? { TMDBImage.url(posterPath, size: "w500") }
    var backdropURL: URL? { TMDBImage.url(backdropPath, size: "w1280") }

    /// TMDB lists like `movie/popular` omit `media_type`; fill it in from the list.
    func withMediaType(_ type: String?) -> MovieInfo {
        var copy = self
        if copy.mediaType == nil { copy.mediaType = type }
        return copy
    }

    /// Most popular first; TMDB ranks search and recommendations by other things.
    static func byPopularity(_ items: [MovieInfo]) -> [MovieInfo] {
        items.sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
    }

    enum CodingKeys: String, CodingKey {
        case tmdbID = "id"
        case title, name, overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case mediaType = "media_type"
        case voteAverage = "vote_average"
        case popularity
    }
}

enum TMDBImage {
    static func url(_ path: String?, size: String) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }
}
