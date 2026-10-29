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
                let err = item.error as NSError?
                var parts = ["Stream failed: \(err?.localizedDescription ?? "unknown error")"]
                if let err {
                    parts.append("code \(err.domain) \(err.code)")
                    if let under = err.userInfo[NSUnderlyingErrorKey] as? NSError {
                        parts.append("underlying \(under.domain) \(under.code): \(under.localizedDescription)")
                    }
                }
                if let ev = item.errorLog()?.events.last {
                    parts.append("http \(ev.errorStatusCode) \(ev.errorComment ?? "")")
                }
                self?.errorMessage = parts.joined(separator: "\n")
            }
        let newPlayer = AVPlayer(playerItem: item)
        self.player = newPlayer
        newPlayer.play()
    }
}
