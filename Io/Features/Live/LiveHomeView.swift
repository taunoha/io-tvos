import SwiftUI

struct LiveHomeView: View {
    static let carouselScrollDuration = 0.25

    @Environment(\.openProgrammeDetail) private var openProgramme
    @Environment(ProgrammeFavorites.self) private var favorites
    @Environment(WatchHistory.self) private var history
    @State private var selectedChannel: LiveChannel?
    @State private var programmeToOpen: Programme?
    @State private var programmeDetail: Programme?
    @FocusState private var focusedChannelID: String?
    @State private var featuredChannelID = LiveChannel.all.first?.id
    @State private var carouselPosition = LiveChannel.all.first?.id
    @State private var visibleChannelID: String?
    @State private var isChannelRowVisible = false
    @Namespace private var channelFocusScope
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.resetFocus) private var resetFocus

    private var carouselBottomInset: CGFloat {
        favorites.entries.isEmpty && history.inProgress.isEmpty ? 0 : IoDesign.focusRoom
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(alignment: .leading, spacing: IoDesign.shelfGap) {
                    channelCarousel(width: viewport.size.width, height: channelCardHeight(in: viewport))

                    if !favorites.entries.isEmpty {
                        ProgrammeRow(title: String(localized: "live.home.favorites"), items: favorites.entries.map(\.programme), openProgramme: openProgramme)
                            .task { await favorites.resolveLegacyArtwork() }
                    }

                    if !history.inProgress.isEmpty {
                        ProgrammeRow(title: String(localized: "live.home.continueShelf"), items: history.inProgress.prefix(7).map(\.programme), allowsRemovingProgress: true, openProgramme: openProgramme)
                    }
                }
                .padding(.vertical, IoDesign.focusRoom)
            }
        }
        .ignoresSafeArea(.container, edges: .horizontal)
        .focusScope(channelFocusScope)
        .onAppear {
            guard programmeToOpen == nil, programmeDetail == nil else { return }
            focusedChannelID = featuredChannelID
            resetFocus(in: channelFocusScope)
        }
        .onChange(of: focusedChannelID) { _, channelID in
            guard let channelID else { return }
            featuredChannelID = channelID
            withAnimation(reduceMotion ? nil : .easeOut(duration: Self.carouselScrollDuration)) {
                carouselPosition = channelID
            }
        }
        .fullScreenCover(item: $selectedChannel, onDismiss: {
            if let programmeToOpen {
                // Keep the destination in this tab while tvOS restores focus after dismissal.
                programmeDetail = programmeToOpen
                self.programmeToOpen = nil
            } else {
                focusedChannelID = featuredChannelID
            }
        }) { channel in
            LivePlayerScreen(channel: channel) { programmeToOpen = $0 }
        }
        .programmeDetailDestination($programmeDetail)
    }

    private func channelCardHeight(in viewport: GeometryProxy) -> CGFloat {
        let hasShelf = !favorites.entries.isEmpty || !history.inProgress.isEmpty
        let shelfPreview = IoDesign.shelfGap + IoDesign.sectionTitleLineHeight
            + IoDesign.sectionHeadingGap + IoDesign.focusRoom + IoDesign.landscapeCardArtworkHeight * 2 / 3
        let channelCaption = IoDesign.sectionHeadingGap + IoDesign.liveChannelCaptionHeight
        let reservedHeight = channelCaption + carouselBottomInset + IoDesign.focusRoom
            + (hasShelf ? shelfPreview : IoDesign.focusRoom)
        // Shelves draw through the bottom safe area before the viewer scrolls to them.
        let visibleHeight = viewport.size.height + (hasShelf ? viewport.safeAreaInsets.bottom : 0)
        return max(IoDesign.liveCardMinimumHeight, visibleHeight - reservedHeight)
    }

    private func channelCarousel(width: CGFloat, height: CGFloat) -> some View {
        let cardWidth = max(1, width - IoDesign.contentInset * 2)
        return VStack(alignment: .leading, spacing: IoDesign.sectionHeadingGap) {
            ScrollView(.horizontal) {
                HStack(spacing: IoDesign.cardGap) {
                    ForEach(LiveChannel.all) { channel in
                        let isFocused = focusedChannelID == channel.id
                        Button { selectedChannel = channel } label: {
                            LiveChannelCard(channel: channel, width: cardWidth, height: height,
                                            isFocused: isFocused,
                                            isPreviewVisible: isChannelRowVisible && visibleChannelID == channel.id,
                                            allowsLivePreview: selectedChannel == nil
                                                && programmeToOpen == nil && programmeDetail == nil
                                                && scenePhase == .active)
                        }
                        .ioCustomButtonFocus()
                        .accessibilityIdentifier("live-channel-\(channel.id)")
                        .focused($focusedChannelID, equals: channel.id)
                        .prefersDefaultFocus(channel.id == featuredChannelID, in: channelFocusScope)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, IoDesign.contentInset, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $carouselPosition, anchor: .leading)
            .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.6) { channelIDs in
                // Only the main card clears this threshold. The adjacent cards peek in at the edges.
                visibleChannelID = channelIDs.first
            }
            .onScrollVisibilityChange(threshold: 0.01) { visible in
                isChannelRowVisible = visible
            }

            HStack(spacing: IoDesign.Space.large) {
                ForEach(LiveChannel.all) { channel in
                    Text(channel.title)
                        .font(IoDesign.metadata)
                        .foregroundStyle(channel.id == featuredChannelID ? .white : .white.opacity(0.62))
                        .padding(.bottom, IoDesign.Space.xSmall)
                        .overlay(alignment: .bottom) {
                            if channel.id == featuredChannelID {
                                Capsule().fill(.white).frame(height: IoDesign.Space.xxSmall)
                            }
                        }
                }
            }
            .frame(height: IoDesign.liveChannelCaptionHeight)
            .padding(.horizontal, IoDesign.contentInset)
            .accessibilityHidden(true)
        }
        .padding(.bottom, carouselBottomInset)
        .ioFullWidthFocusSection()
    }
}
