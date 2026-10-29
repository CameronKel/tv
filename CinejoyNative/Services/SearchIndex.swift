import Foundation

/// Well-known titles for search-as-you-type.
///
/// TMDB's search matches whole words, so "break" never finds "Breaking Bad".
/// This keeps the most-voted movies and shows (plus this week's trending) on
/// the device and matches the start of any word in their names.
actor SearchIndex {
    static let shared = SearchIndex()

    private static let pagesPerType = 30
    private static let maxAge: TimeInterval = 7 * 24 * 3600

    private struct Cache: Codable {
        let date: Date
        let items: [MovieInfo]
    }

    private var entries: [(name: String, media: MovieInfo)] = []
    private var loadTask: Task<[MovieInfo], Never>?

    /// Starts building the index so the first search doesn't wait.
    func warmUp() async {
        _ = await load()
    }

    func matches(_ query: String) async -> [MovieInfo] {
        await load()
        let q = Self.normalize(query)
        guard !q.isEmpty else { return [] }
        return entries
            .filter { $0.name.hasPrefix(q) || $0.name.contains(" " + q) }
            .map(\.media)
    }

    @discardableResult
    private func load() async -> Bool {
        if !entries.isEmpty { return true }
        let task = loadTask ?? Task { await Self.build() }
        loadTask = task
        let items = await task.value
        if entries.isEmpty {
            entries = items.map { (name: Self.normalize($0.displayName), media: $0) }
        }
        return !entries.isEmpty
    }

    // MARK: - Building

    private static func build() async -> [MovieInfo] {
        let cached = readCache()
        if let cached, Date().timeIntervalSince(cached.date) < maxAge {
            return cached.items
        }
        let fresh = await fetchAll()
        guard !fresh.isEmpty else { return cached?.items ?? [] }
        writeCache(Cache(date: Date(), items: fresh))
        return fresh
    }

    private static func fetchAll() async -> [MovieInfo] {
        var requests: [(path: String, query: [String: String], type: String?)] = []
        for type in ["movie", "tv"] {
            for page in 1...pagesPerType {
                requests.append(("discover/\(type)",
                                 ["sort_by": "vote_count.desc", "page": String(page)], type))
            }
        }
        for page in 1...5 {
            requests.append(("trending/all/week", ["page": String(page)], nil))
        }

        let pages = await withTaskGroup(of: [MovieInfo].self) { group -> [[MovieInfo]] in
            for request in requests {
                group.addTask {
                    (try? await CinejoyAPI.shared.list(
                        request.path, query: request.query, mediaType: request.type)) ?? []
                }
            }
            var results: [[MovieInfo]] = []
            for await page in group { results.append(page) }
            return results
        }

        var seen = Set<String>()
        return pages.joined().filter { seen.insert($0.id).inserted }
    }

    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let words = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return words.filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: - Disk cache

    private static var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("search-index-v1.json")
    }

    private static func readCache() -> Cache? {
        guard let url = cacheURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Cache.self, from: data)
    }

    private static func writeCache(_ cache: Cache) {
        guard let url = cacheURL, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
