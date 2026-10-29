import Foundation

struct MovieInfo: Identifiable, Hashable, Codable {
    let tmdbID: Int
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let mediaType: String?

    var id: Int { tmdbID }

    var displayTitle: String {
        let t = title ?? name ?? "Unknown"
        let date = releaseDate ?? firstAirDate
        if let date, date.count >= 4 {
            return "\(t) (\(date.prefix(4)))"
        }
        return t
    }

    var posterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(path)")
    }

    enum CodingKeys: String, CodingKey {
        case tmdbID = "id"
        case title, name, overview
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case mediaType = "media_type"
    }
}
