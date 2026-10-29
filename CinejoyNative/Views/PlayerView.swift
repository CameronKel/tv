import SwiftUI
import AVKit

struct PlayerView: View {
    let player: AVPlayer

    var body: some View {
        VideoPlayer(player: player)
            .onDisappear { player.pause() }
    }
}
