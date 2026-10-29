import SwiftUI
import AVKit

/// Full-screen player: a spinner while the stream resolves, then the video.
/// Errors show on top with a Back button.
struct PlayerScreen: View {
    @EnvironmentObject private var playback: PlaybackViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = playback.player {
                VideoPlayer(player: player).ignoresSafeArea()
            } else if playback.errorMessage == nil {
                VStack(spacing: 30) {
                    ProgressView()
                    Text(playback.nowPlayingTitle).font(.headline)
                    Text("Preparing stream…").foregroundStyle(.secondary)
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
}
