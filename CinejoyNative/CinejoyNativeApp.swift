import SwiftUI

@main
struct CinejoyNativeApp: App {
    init() {
        // Posters and backdrops are re-shown constantly across rows; keep them cached.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20, directory: nil)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
