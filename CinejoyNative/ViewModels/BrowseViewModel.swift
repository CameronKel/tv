import Foundation

/// Loads a tab's rows in parallel, keeping the catalog's order.
@MainActor
final class BrowseViewModel: ObservableObject {
    @Published private(set) var shelves: [Shelf] = []
    @Published private(set) var hero: MovieInfo?
    @Published private(set) var errorMessage: String?

    private let specs: [ShelfSpec]

    init(specs: [ShelfSpec]) {
        self.specs = specs
    }

    func load() async {
        guard shelves.isEmpty else { return }
        errorMessage = nil
        let specs = self.specs

        let loaded = await withTaskGroup(of: (Int, [MovieInfo]).self) { group -> [(Int, [MovieInfo])] in
            for (index, spec) in specs.enumerated() {
                group.addTask {
                    let items = try? await CinejoyAPI.shared.list(
                        spec.path, query: spec.query, mediaType: spec.mediaType)
                    return (index, items ?? [])
                }
            }
            var results: [(Int, [MovieInfo])] = []
            for await result in group { results.append(result) }
            return results
        }

        shelves = loaded
            .sorted { $0.0 < $1.0 }
            .filter { !$0.1.isEmpty }
            .map { Shelf(id: specs[$0.0].title, title: specs[$0.0].title, items: $0.1) }
        hero = shelves.first?.items.first { $0.backdropPath != nil }
        if shelves.isEmpty {
            errorMessage = "Couldn't load anything. Check the connection and try again."
        }
    }
}

/// "Because you watched …" rows from the two most recent titles.
@MainActor
final class RecommendationsModel: ObservableObject {
    @Published private(set) var shelves: [Shelf] = []

    func load(from entries: [WatchEntry]) async {
        let watched = Set(entries.map(\.id))
        var result: [Shelf] = []
        for seed in entries.prefix(2).map(\.media) {
            let type = seed.isTV ? "tv" : "movie"
            guard let items = try? await CinejoyAPI.shared.list(
                "\(type)/\(seed.tmdbID)/recommendations", mediaType: type) else { continue }
            let fresh = items.filter { !watched.contains($0.id) }
            if !fresh.isEmpty {
                result.append(Shelf(id: "rec-\(seed.id)",
                                    title: "Because you watched \(seed.displayName)", items: fresh))
            }
        }
        shelves = result
    }
}
