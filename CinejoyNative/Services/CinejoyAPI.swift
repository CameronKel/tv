import Foundation

enum APIError: Error, LocalizedError {
    case badURL
    case badResponse(Int)
    case decodingError(Error)
    case noResults
    case missingConfiguration

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid URL"
        case .badResponse(let code): return "Server responded with \(code)"
        case .decodingError(let e): return "Decoding failed: \(e.localizedDescription)"
        case .noResults: return "No stream URL found"
        case .missingConfiguration: return "TMDB_API_KEY not set in Info.plist"
        }
    }
}

final class CinejoyAPI {
    static let shared = CinejoyAPI()
    private let session = URLSession.shared

    private let tmdbAPIKey: String = {
        Bundle.main.infoDictionary?["TMDB_API_KEY"] as? String ?? ""
    }()

    // MARK: - TMDB search
    func search(query: String) async throws -> [MovieInfo] {
        guard !tmdbAPIKey.isEmpty,
              tmdbAPIKey != "REPLACE_WITH_YOUR_TMDB_V3_API_KEY" else {
            throw APIError.missingConfiguration
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        var comps = URLComponents(string: "https://api.themoviedb.org/3/search/multi")!
        comps.queryItems = [
            .init(name: "api_key", value: tmdbAPIKey),
            .init(name: "query", value: trimmed),
            .init(name: "include_adult", value: "false"),
            .init(name: "language", value: "en-US"),
            .init(name: "page", value: "1"),
        ]
        guard let url = comps.url else { throw APIError.badURL }

        let (data, resp) = try await session.data(from: url)
        guard let http = resp as? HTTPURLResponse else { throw APIError.badResponse(-1) }
        guard (200..<300).contains(http.statusCode) else { throw APIError.badResponse(http.statusCode) }

        struct SearchResponse: Codable { let results: [MovieInfo] }
        do {
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            return decoded.results.filter {
                $0.mediaType == "movie" || $0.mediaType == "tv"
            }
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - IMDB ID from TMDB external_ids
    func fetchIMDBID(tmdbID: Int, mediaType: String = "movie") async throws -> String {
        guard !tmdbAPIKey.isEmpty else { throw APIError.missingConfiguration }
        let path = mediaType == "tv"
            ? "https://api.themoviedb.org/3/tv/\(tmdbID)/external_ids"
            : "https://api.themoviedb.org/3/movie/\(tmdbID)/external_ids"
        var comps = URLComponents(string: path)!
        comps.queryItems = [.init(name: "api_key", value: tmdbAPIKey)]
        guard let url = comps.url else { throw APIError.badURL }

        let (data, _) = try await session.data(from: url)
        struct ExternalIDs: Codable { let imdb_id: String? }
        return try JSONDecoder().decode(ExternalIDs.self, from: data).imdb_id ?? ""
    }

    // MARK: - api.wing.st/info (detail view)
    struct CinejoyInfo: Codable {
        let title: String?
        let year: String?
        let imdb: String?
        let overview: String?
        let poster: String?
        let backdrop: String?
        let runtime: Int?
        let genres: [String]?
    }

    func fetchInfo(tmdbID: Int, mediaType: String = "movie") async throws -> CinejoyInfo {
        var comps = URLComponents(string: "https://api.wing.st/info")!
        comps.queryItems = [
            .init(name: "type", value: mediaType),
            .init(name: "tmdb", value: String(tmdbID)),
        ]
        guard let url = comps.url else { throw APIError.badURL }
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(CinejoyInfo.self, from: data)
    }

    // MARK: - Stream URL (native, no proxy)
    func resolveMovieStreamURL(
        tmdbID: Int, imdbID: String, year: String, title: String
    ) async throws -> URL {
        try await NativeStreamResolver.resolveMovieStreamURL(
            tmdbID: tmdbID, imdbID: imdbID, year: year, title: title
        )
    }

    func resolveTVStreamURL(
        tmdbID: Int, imdbID: String, year: String, title: String,
        season: Int, episode: Int
    ) async throws -> URL {
        try await NativeStreamResolver.resolveTVStreamURL(
            tmdbID: tmdbID, imdbID: imdbID, year: year, title: title,
            season: season, episode: episode
        )
    }
}
