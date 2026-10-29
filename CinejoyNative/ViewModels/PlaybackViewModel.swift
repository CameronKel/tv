import AVFoundation
import SwiftUI

@MainActor
final class PlaybackViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func startPlayback(url: URL) {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let asset = HLSResourceLoader.asset(for: url)
        let item = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: item)
        self.player = newPlayer
        newPlayer.play()
    }
}
