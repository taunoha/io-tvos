import SwiftUI

// Shared typography and spacing for browsing views. Sizes are in tvOS points.
enum IoDesign {
    static let pageTitle = Font.system(size: 57, weight: .bold)
    static let sectionTitle = Font.system(size: 38, weight: .semibold)
    static let cardTitle = Font.system(size: 29, weight: .semibold)
    static let body = Font.system(size: 29)
    static let metadata = Font.system(size: 25, weight: .medium)
    static let contentInset: CGFloat = 90
    static let cardGap: CGFloat = 40
    static let focusRoom: CGFloat = 24
    // A row contributes another 24 pt below its cards: 24 + 40 = 64.
    static let shelfGap: CGFloat = 40

    static let playerInfoWidth: CGFloat = 1200
    static let playerInfoHeight: CGFloat = 260
    static let playerInfoLiveHeight: CGFloat = 360
    static let playerInfoHorizontalPadding: CGFloat = 32
    static let playerInfoVerticalPadding: CGFloat = 20
    static let playerInfoHorizontalInset: CGFloat = 48
    static let playerInfoCornerRadius: CGFloat = 24
    static let playerInfoRowSpacing: CGFloat = 10
    static let playerInfoColumnSpacing: CGFloat = 16
    static let playerInfoMarkerWidth: CGFloat = 32
    static let playerInfoLabelWidth: CGFloat = 160
    static let playerInfoTimeSpacing: CGFloat = 2
}
