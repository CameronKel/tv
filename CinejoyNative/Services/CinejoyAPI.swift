import Foundation

enum APIError: Error, LocalizedError {
    case badURL
    case badResponse(Int)
    case decodingError(Error)
    case noResults
    case missingConfiguration
    case wasmMissing
    case wasmNoMemory
    case wasmAllocFailed

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid URL"
        case .badResponse(let code): return "Server responded with \(code)"
        case .decodingError(let e): return "Decoding failed: \(e.localizedDescription)"
        case .noResults: return "No stream URL found"
        case .missingConfiguration: return "TMDB_API_KEY not set in Info.plist"
        case .wasmMissing: return "crush.wasm not found in app bundle"
        case .wasmNoMemory: return "crush.wasm has no exported memory"
        case .wasmAllocFailed: return "crush.wasm alloc returned a null pointer"
        }
    }
}

final class CinejoyAPI: @unchecked Sendable {
    static let shared = CinejoyAPI()
    let session = URLSession.shared
    /// URLSession's default is 60 s; a stalled request shouldn't hold up Play that long.
    static let timeout: TimeInterval = 15

    let tmdbAPIKey: String = {
        Bundle.main.infoDictionary?["TMDB_API_KEY"] as? String ?? ""
    }()

    // MARK: - TMDB search
    /// TMDB matches whole words and ranks by text match, so "break" never
    /// finds Breaking Bad. Merge word-prefix matches from the local index of
    /// well-known titles with two pages of TMDB results, most popular first.
    func search(query: String) async throws -> [MovieInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        func page(_ n: Int) async throws -> [MovieInfo] {
            try await list("search/multi", query: [
                "query": trimmed, "include_adult": "false", "page": String(n),
            ])
        }
        async let local = SearchIndex.shared.matches(trimmed)
        async let first = page(1)
        async let second = page(2)

        let known = await local
        var remote: [MovieInfo] = []
        do {
            remote = try await first
        } catch {
            if known.isEmpty { throw error }
        }
        remote += (try? await second) ?? []

        var seen = Set<String>()
        return MovieInfo.byPopularity((known + remote).filter { seen.insert($0.id).inserted })
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

        let (data, _) = try await session.data(for: URLRequest(url: url, timeoutInterval: Self.timeout))
        struct ExternalIDs: Codable { let imdb_id: String? }
        return try JSONDecoder().decode(ExternalIDs.self, from: data).imdb_id ?? ""
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
