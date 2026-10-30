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

    /// Play and the like. Apple TV's default button already reads as one when
    /// focused; on iPad a default button is bare blue text.
    func primaryAction() -> some View {
        #if os(tvOS)
        self
        #else
        buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
        #endif
    }

    /// My List, Details, unselected seasons: a filled grey button on iPad.
    func secondaryAction() -> some View {
        #if os(tvOS)
        self
        #else
        buttonStyle(.bordered).tint(.white)
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
