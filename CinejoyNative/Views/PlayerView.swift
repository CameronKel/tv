import SwiftUI
import AVKit

struct PlayerView: View {
    let player: AVPlayer
    let errorMessage: String?

    var body: some View {
        VideoPlayer(player: player)
            .overlay(alignment: .center) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .padding(40)
                        .background(.black.opacity(0.85))
                        .cornerRadius(20)
                        .padding(80)
                }
            }
            .onDisappear { player.pause() }
    }
}
