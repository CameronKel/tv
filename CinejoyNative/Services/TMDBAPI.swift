import Foundation

/// TMDB browsing: lists, details, seasons, and the stream lookup that ties
/// a TMDB title to the Cinejoy resolver.
extension CinejoyAPI {

    func tmdb<T: Decodable>(_ path: String, query: [String: String] = [:], as type: T.Type) async throws -> T {
        guard !tmdbAPIKey.isEmpty else { throw APIError.missingConfiguration }
        var comps = URLComponents(string: "https://api.themoviedb.org/3/\(path)")!
        comps.queryItems = [
            URLQueryItem(name: "api_key", value: tmdbAPIKey),
            URLQueryItem(name: "language", value: "en-US"),
        ] + query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps.url else { throw APIError.badURL }

        let (data, resp) = try await session.data(for: URLRequest(url: url, timeoutInterval: Self.timeout))
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.badResponse(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// A TMDB list, keeping only movies and shows that have a poster.
    func list(_ path: String, query: [String: String] = [:], mediaType: String? = nil) async throws -> [MovieInfo] {
        try await tmdb(path, query: query, as: MediaPage.self).results
            .map { $0.withMediaType(mediaType) }
            .filter { ($0.mediaType == "movie" || $0.mediaType == "tv") && $0.posterPath != nil }
    }

    func details(for media: MovieInfo) async throws -> MediaDetails {
        let details = try await tmdb(
            "\(media.isTV ? "tv" : "movie")/\(media.tmdbID)",
            query: ["append_to_response": "recommendations,external_ids"],
            as: MediaDetails.self
        )
        // So pressing Play on this page needs no extra lookup.
        if let imdb = details.externalIDs?.imdbID, !imdb.isEmpty {
            IMDBIDCache.shared[media.id] = imdb
        }
        return details
    }

    func season(showID: Int, number: Int) async throws -> SeasonDetails {
        try await tmdb("tv/\(showID)/season/\(number)", as: SeasonDetails.self)
    }

    /// The episode after S`season`E`episode`, crossing into the next season.
    func nextEpisode(showID: Int, season: Int, episode: Int) async -> (season: Int, episode: Int)? {
        guard let details = try? await tmdb("tv/\(showID)", as: MediaDetails.self) else { return nil }
        let seasons = details.playableSeasons
        if let current = seasons.first(where: { $0.seasonNumber == season }),
           episode < (current.episodeCount ?? 0) {
            return (season, episode + 1)
        }
        if let next = seasons.first(where: { $0.seasonNumber > season }) {
            return (next.seasonNumber, 1)
        }
        return nil
    }

    /// Looks up the IMDB id the resolver needs (cached once the detail page has
    /// loaded) and resolves the stream.
    func streamURL(for media: MovieInfo, season: Int?, episode: Int?) async throws -> URL {
        var imdb = IMDBIDCache.shared[media.id] ?? ""
        if imdb.isEmpty {
            imdb = (try? await fetchIMDBID(tmdbID: media.tmdbID, mediaType: media.isTV ? "tv" : "movie")) ?? ""
            if !imdb.isEmpty { IMDBIDCache.shared[media.id] = imdb }
        }
        let year = media.year ?? ""
        let title = media.displayName

        if media.isTV {
            return try await resolveTVStreamURL(
                tmdbID: media.tmdbID, imdbID: imdb, year: year, title: title,
                season: season ?? 1, episode: episode ?? 1
            )
        }
        return try await resolveMovieStreamURL(
            tmdbID: media.tmdbID, imdbID: imdb, year: year, title: title
        )
    }
}

/// IMDB ids by `MovieInfo.id`, for this launch. They never change, and
/// episodes of a show share one, so each title is looked up once.
final class IMDBIDCache: @unchecked Sendable {
    static let shared = IMDBIDCache()

    private var ids: [String: String] = [:]
    private let lock = NSLock()

    subscript(id: String) -> String? {
        get { lock.lock(); defer { lock.unlock() }; return ids[id] }
        set { lock.lock(); defer { lock.unlock() }; ids[id] = newValue }
    }
}
