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
    static let inlineIcon = Font.system(size: 13, weight: .semibold)

    static let scheduleCellTitle = Font.system(size: 27, weight: .semibold)
    static let scheduleDetailTitle = Font.system(size: 44, weight: .semibold)
    static let scheduleArtworkHeight = Space.xxxLarge + Space.xLarge
    static let scheduleArtworkWidth = scheduleArtworkHeight * 16 / 9
    static let scheduleTimeLabel = caption.monospacedDigit()
    static let scheduleChannelWidth = Space.xxxLarge + Space.xxLarge
    static let scheduleRowHeight = Space.xxLarge + Space.xLarge
    static let scheduleAxisHeight = Space.xLarge
    static let scheduleEdgeShadowWidth = Space.xLarge
    static let scheduleGridCornerRadius = Space.medium
    static let schedulePanelCornerRadius: CGFloat = 20

    static let contentInset = Space.xxxLarge
    static let cardGap = Space.xLarge
    static let focusRoom = Space.large
    static let sectionHeadingGap = Space.small
    static let shelfGap = Space.xLarge

    static let playerInfoWidth: CGFloat = 1200
    static let playerInfoHeight: CGFloat = 260
    static let playerInfoLiveHeight: CGFloat = 360
    static let playerInfoHorizontalPadding = Space.xLarge
    static let playerInfoVerticalPadding = Space.large
    static let playerInfoHorizontalInset = Space.xxLarge
    static let playerInfoCornerRadius: CGFloat = 24
    static let playerInfoRowSpacing = Space.small
    static let playerInfoColumnSpacing = Space.medium
    static let playerInfoMarkerWidth: CGFloat = 32
    static let playerInfoLabelWidth: CGFloat = 160
    static let playerInfoTimeSpacing = Space.xxSmall
}

private struct IoCustomFocusButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

extension View {
    /// Use when the button label draws its own focus state.
    func ioCustomButtonFocus() -> some View {
        buttonStyle(IoCustomFocusButtonStyle())
            .focusEffectDisabled()
            .hoverEffectDisabled()
    }
}
