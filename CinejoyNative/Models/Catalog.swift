import Foundation

/// One horizontal row of titles, fetched from a TMDB list endpoint.
struct ShelfSpec {
    let title: String
    let path: String
    var query: [String: String] = [:]
    var mediaType: String? = nil
}

struct Shelf: Identifiable {
    let id: String
    let title: String
    let items: [MovieInfo]
}

/// The rows each tab shows.
enum Catalog {
    static let home: [ShelfSpec] = [
        .init(title: "Trending This Week", path: "trending/all/week"),
        .init(title: "Popular Movies", path: "movie/popular", mediaType: "movie"),
        .init(title: "Popular TV Shows", path: "tv/popular", mediaType: "tv"),
        .init(title: "Top Rated Movies", path: "movie/top_rated", mediaType: "movie"),
        .init(title: "Top Rated TV Shows", path: "tv/top_rated", mediaType: "tv"),
    ]

    static let movies: [ShelfSpec] = [
        .init(title: "Trending Movies", path: "trending/movie/week", mediaType: "movie"),
        .init(title: "In Theatres", path: "movie/now_playing", mediaType: "movie"),
        .init(title: "Popular", path: "movie/popular", mediaType: "movie"),
        .init(title: "Top Rated", path: "movie/top_rated", mediaType: "movie"),
    ] + genres([
        ("Action", 28), ("Comedy", 35), ("Science Fiction", 878), ("Horror", 27),
        ("Thriller", 53), ("Animation", 16), ("Drama", 18), ("Romance", 10749),
        ("Documentary", 99),
    ], type: "movie")

    static let tv: [ShelfSpec] = [
        .init(title: "Trending Shows", path: "trending/tv/week", mediaType: "tv"),
        .init(title: "Popular", path: "tv/popular", mediaType: "tv"),
        .init(title: "Top Rated", path: "tv/top_rated", mediaType: "tv"),
        .init(title: "On the Air", path: "tv/on_the_air", mediaType: "tv"),
    ] + genres([
        ("Drama", 18), ("Comedy", 35), ("Crime", 80), ("Sci-Fi & Fantasy", 10765),
        ("Action & Adventure", 10759), ("Animation", 16), ("Mystery", 9648),
        ("Reality", 10764), ("Documentary", 99),
    ], type: "tv")

    private static func genres(_ list: [(String, Int)], type: String) -> [ShelfSpec] {
        list.map { name, id in
            ShelfSpec(
                title: name,
                path: "discover/\(type)",
                query: [
                    "with_genres": String(id),
                    "sort_by": "popularity.desc",
                    "vote_count.gte": "200",
                ],
                mediaType: type
            )
        }
    }
}
