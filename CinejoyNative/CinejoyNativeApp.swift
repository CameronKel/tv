import AVFoundation
import SwiftUI

@main
struct CinejoyNativeApp: App {
    init() {
        // Posters and backdrops are re-shown constantly across rows; keep them cached.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20, directory: nil)
        #if os(iOS)
        // Sound with the silent switch on, and picture-in-picture when leaving the app.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
