import SwiftUI
import AVKit

/// Full-screen player: a spinner while the stream resolves, then the system
/// player with the show controls (`PlayerController`).
/// Errors show on top with a Back button.
struct PlayerScreen: View {
    @EnvironmentObject private var playback: PlaybackViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = playback.player {
                PlayerController(player: player, actions: playback.actions,
                                 episodes: episodesTab, perform: playback.perform)
                    .ignoresSafeArea()
            } else if playback.errorMessage == nil {
                VStack(spacing: 30) {
                    ProgressView()
                    Text(playback.nowPlayingTitle).font(.headline)
                    Text(playback.status).foregroundStyle(.secondary)
                    Button("Cancel") { playback.isPresented = false }
                        .padding(.top, 20)
                }
            }

            if let message = playback.errorMessage {
                VStack(spacing: 30) {
                    Text(message)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                    Button("Back") { playback.isPresented = false }
                }
                .padding(50)
                .background(Color.black.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .padding(80)
            }
        }
    }

    private var episodesTab: AnyView? {
        guard let show = playback.currentShow else { return nil }
        return AnyView(
            PlayerEpisodesView(show: show, startSeason: playback.currentSeason ?? 1)
                .environmentObject(playback)
                .environmentObject(WatchHistory.shared)
        )
    }
}
