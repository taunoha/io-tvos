import SwiftUI

enum IoDesign {
    // Adjacent Fibonacci steps approximate the golden ratio at whole points.
    enum Space {
        static let xxSmall: CGFloat = 3
        static let xSmall: CGFloat = 5
        static let small: CGFloat = 8
        static let medium: CGFloat = 13
        static let large: CGFloat = 21
        static let xLarge: CGFloat = 34
        static let xxLarge: CGFloat = 55
        static let xxxLarge: CGFloat = 89
    }

    // Perfect Fourth: take each step from 60 pt and round to whole points.
    static let pageTitle = Font.system(size: 60, weight: .bold)
    static let sectionTitle = Font.system(size: 45, weight: .semibold)
    static let cardTitle = Font.system(size: 34, weight: .semibold)
    static let body = Font.system(size: 25)
    static let minimumTextSize: CGFloat = 23
    static let metadata = Font.system(size: minimumTextSize, weight: .medium)
    static let caption = Font.system(size: minimumTextSize)
    static let badge = Font.system(size: minimumTextSize, weight: .bold)
    static let tabIconSize: CGFloat = 25

    static let scheduleCellTitle = Font.system(size: 27, weight: .semibold)
    static let scheduleDetailTitle = Font.system(size: 44, weight: .semibold)
    static let scheduleArtworkHeight = Space.xxxLarge + Space.xLarge * 2
    static let scheduleArtworkWidth = scheduleArtworkHeight * 16 / 9
    static let scheduleTimeLabel = caption.monospacedDigit()
    static let scheduleChannelWidth = Space.xxxLarge + Space.xxLarge
    static let scheduleRowHeight = Space.xxLarge + Space.xLarge
    static let scheduleAxisHeight = Space.xLarge
    static let scheduleEdgeShadowWidth = Space.xLarge
    static let scheduleGridCornerRadius = Space.medium
    static let schedulePanelCornerRadius: CGFloat = 20

    static let contentInset = Space.xxxLarge
    static let landscapeCardWidth: CGFloat = 360
    static let landscapeCardArtworkHeight: CGFloat = 203
    static let portraitCardWidth: CGFloat = 280
    static let cardCornerRadius: CGFloat = 20
    static let cardGap = Space.xLarge
    static let focusRoom = Space.large
    static let sectionHeadingGap = Space.small
    static let shelfGap = Space.xLarge
    static let programmeInfoContentInset = Space.large * 1.5
    static let programmeInfoDescriptionMaxWidth: CGFloat = 1050

    static let playerInfoWidth: CGFloat = 1200
    static let playerInfoHeight: CGFloat = 260
    static let playerProgrammeShelfHeight = landscapeCardArtworkHeight + Space.xxxLarge * 2
    static let playerInfoHorizontalInset = Space.xLarge
    static let playerInfoCornerRadius: CGFloat = 24
}

struct IoSelectionPillLabel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let isSelected: Bool
    let isFocused: Bool

    var body: some View {
        Text(title)
            .font(IoDesign.body.weight(.semibold))
            .padding(.horizontal, IoDesign.Space.large)
            .padding(.vertical, IoDesign.Space.small)
            .foregroundStyle(isFocused ? .black : .white)
            .background(isFocused ? .white : .white.opacity(isSelected ? 0.18 : 0.08), in: Capsule())
            .overlay {
                Capsule().strokeBorder(.white.opacity(0.55), lineWidth: isSelected && !isFocused ? 1 : 0)
            }
            .scaleEffect(isFocused && !reduceMotion ? 1.06 : 1)
    }
}

private struct IoCustomFocusButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

extension View {
    /// Give vertical focus moves a target across the row's available width.
    func ioFullWidthFocusSection() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .focusSection()
    }

    /// Use when the button label draws its own focus state.
    func ioCustomButtonFocus() -> some View {
        buttonStyle(IoCustomFocusButtonStyle())
            .focusEffectDisabled()
            .hoverEffectDisabled()
    }
}
