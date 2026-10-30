import AVKit
import SwiftUI

/// The system player (AVPlayerViewController). On Apple TV it carries the
/// show controls tvOS gives it room for: contextual actions for Skip Intro /
/// Next Episode, and an Episodes tab in the swipe-down info panel. iPad has
/// neither, so `PlayerScreen` draws those buttons over the video there.
struct PlayerController: UIViewControllerRepresentable {
    let player: AVPlayer
    let actions: [PlaybackViewModel.PlayerAction]
    /// Content of the Episodes tab; nil for movies.
    let episodes: AnyView?
    let perform: @MainActor (PlaybackViewModel.PlayerAction) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        #if os(tvOS)
        if let episodes {
            let tab = UIHostingController(rootView: episodes)
            tab.title = "Episodes"
            tab.preferredContentSize = CGSize(width: 0, height: 400)
            controller.customInfoViewControllers = [tab]
        }
        #else
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        #endif
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        #if os(tvOS)
        // Rebuilding the buttons on every SwiftUI update would make them flicker.
        guard context.coordinator.shown != actions else { return }
        context.coordinator.shown = actions
        let perform = self.perform
        controller.contextualActions = actions.map { action in
            UIAction(title: action.title, image: UIImage(systemName: action.icon)) { _ in
                Task { @MainActor in perform(action) }
            }
        }
        #endif
    }

    final class Coordinator {
        var shown: [PlaybackViewModel.PlayerAction] = []
    }
}

/// The Episodes tab: the playing show's seasons and episodes, compact.
struct PlayerEpisodesView: View {
    let show: MovieInfo
    let startSeason: Int

    @State private var seasons: [SeasonSummary] = []
    @State private var season: Int?
    @State private var episodesBySeason: [Int: [Episode]] = [:]

    var body: some View {
        EpisodesSection(
            media: show, seasons: seasons, selectedSeason: $season,
            episodes: season.flatMap { episodesBySeason[$0] } ?? [],
            isLoading: season.map { episodesBySeason[$0] == nil } ?? true,
            compact: true
        )
        .task {
            if season == nil { season = startSeason }
            guard seasons.isEmpty,
                  let details = try? await CinejoyAPI.shared.details(for: show) else { return }
            seasons = details.playableSeasons
        }
        .task(id: season) {
            guard let season, episodesBySeason[season] == nil,
                  let loaded = try? await CinejoyAPI.shared.season(showID: show.tmdbID, number: season)
            else { return }
            episodesBySeason[season] = loaded.episodes
        }
    }
}
