import AVFoundation
import Combine
import SwiftUI

@MainActor
final class PlaybackViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var statusObserver: AnyCancellable?

    func startPlayback(url: URL) {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let asset = HLSResourceLoader.asset(for: url)
        let item = AVPlayerItem(asset: asset)
        statusObserver = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] status in
                guard status == .failed, let item else { return }
                self?.errorMessage = "Stream failed: \(item.error?.localizedDescription ?? "unknown error")"
            }
        let newPlayer = AVPlayer(playerItem: item)
        self.player = newPlayer
        newPlayer.play()
    }
}
