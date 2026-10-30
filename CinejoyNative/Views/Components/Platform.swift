import SwiftUI

/// The few places Apple TV and iPad differ. The views are written at TV size
/// (a 1920-point-wide screen seen from the sofa); iPad scales the fixed sizes
/// down, while text styles like `.caption` already adapt per platform.
enum UI {
    #if os(tvOS)
    static let scale: CGFloat = 1
    #else
    static let scale: CGFloat = 0.6
    #endif

    static func s(_ value: CGFloat) -> CGFloat { value * scale }
}

extension View {
    /// Groups a row for the remote's focus engine; iPad has no focus to guide.
    func tvFocusSection() -> some View {
        #if os(tvOS)
        focusSection()
        #else
        self
        #endif
    }

    /// The lifting card look on Apple TV; a plain tappable image on iPad.
    func cardButton() -> some View {
        #if os(tvOS)
        buttonStyle(.card)
        #else
        buttonStyle(.plain)
        #endif
    }
}
