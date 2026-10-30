import SwiftUI
import AVKit

/// Full-screen player: a spinner while the stream resolves, then the system
/// player with the show controls (`PlayerController`).
/// Errors show on top with a Back button.
struct PlayerScreen: View {
    @EnvironmentObject private var playback: PlaybackViewModel
    @State private var showsEpisodes = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = playback.player {
                PlayerController(player: player, actions: playback.actions,
                                 episodes: episodesTab, perform: playback.perform)
                    .ignoresSafeArea()
                #if os(iOS)
                touchControls
                #endif
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

    #if os(iOS)
    /// iPad: close, Episodes, and Skip / Next Episode above the scrubber.
    private var touchControls: some View {
        VStack {
            HStack {
                Button { playback.isPresented = false } label: {
                    Image(systemName: "xmark").font(.title3.bold()).padding(14)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Close")
                Spacer()
                if playback.currentShow != nil {
                    Button { showsEpisodes = true } label: {
                        Label("Episodes", systemImage: "rectangle.stack").font(.headline)
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 70)   // below the player's own top controls
            Spacer()
            HStack(spacing: 16) {
                Spacer()
                ForEach(playback.actions, id: \.title) { action in
                    Button { playback.perform(action) } label: {
                        Label(action.title, systemImage: action.icon).font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 110)   // above the scrubber
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .sheet(isPresented: $showsEpisodes) {
            NavigationStack {
                ScrollView { episodesTab }
                    .navigationTitle("Episodes")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsEpisodes = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }
    #endif
}
