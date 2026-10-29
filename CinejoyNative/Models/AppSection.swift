import SwiftUI

/// The app's sections, in menu order.
enum AppSection: String, CaseIterable, Identifiable {
    case home, movies, tv, search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .movies: return "Movies"
        case .tv: return "TV Shows"
        case .search: return "Search"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .movies: return "film"
        case .tv: return "tv"
        case .search: return "magnifyingglass"
        }
    }
}
