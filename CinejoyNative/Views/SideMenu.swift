import SwiftUI

/// The app's sections, in menu order.
enum AppSection: String, CaseIterable, Identifiable {
    case home, movies, tv, search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .movies: return "Movies"
        case .tv: return "TV Shows"
        case .search: return "Search"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .movies: return "film"
        case .tv: return "tv"
        case .search: return "magnifyingglass"
        }
    }
}

/// A slim column of icons at the screen's edge. It widens to show names
/// while it has focus, and moving through it switches section, like the
/// system tab bar does.
struct SideMenu: View {
    @Binding var selection: AppSection
    @FocusState private var focused: AppSection?

    static let collapsedWidth: CGFloat = 130
    private static let expandedWidth: CGFloat = 360

    private var isExpanded: Bool { focused != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            ForEach(AppSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    SideMenuLabel(section: section, isSelected: selection == section, showsTitle: isExpanded)
                }
                .buttonStyle(SideMenuButtonStyle())
                .focused($focused, equals: section)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(width: isExpanded ? Self.expandedWidth : Self.collapsedWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(
            LinearGradient(colors: [.black.opacity(isExpanded ? 0.98 : 0.75), .black.opacity(isExpanded ? 0.95 : 0.0)],
                           startPoint: .leading, endPoint: .trailing)
                .ignoresSafeArea()
        )
        .focusSection()
        .onChange(of: focused) { section in        // single-value signature for tvOS 16
            if let section { selection = section }
        }
        .animation(.easeOut(duration: 0.2), value: isExpanded)
    }
}

private struct SideMenuLabel: View {
    let section: AppSection
    let isSelected: Bool
    let showsTitle: Bool

    var body: some View {
        HStack(spacing: 22) {
            Image(systemName: section.icon)
                .font(.system(size: 30, weight: .semibold))
                .frame(width: 40)
            if showsTitle {
                Text(section.title)
                    .font(.system(size: 30, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .fixedSize()
                    .transition(.opacity)
            }
        }
        // Relative to the button style's colour, which flips when focused.
        .foregroundStyle(isSelected ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
    }
}

/// A rounded highlight that follows focus, instead of the default lifted card.
private struct SideMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Body(configuration: configuration)
    }

    private struct Body: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .foregroundStyle(isFocused ? Color.black : Color.primary)
                .padding(.vertical, 16)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isFocused ? Color.white : Color.clear)
                )
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}
