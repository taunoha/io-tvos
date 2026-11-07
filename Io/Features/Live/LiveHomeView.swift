import SwiftUI

struct LiveHomeView: View {
    let openProgramme: (Programme) -> Void
    @Environment(ProgrammeFavorites.self) private var favorites
    @Environment(WatchHistory.self) private var history
    @State private var selectedChannel: LiveChannel?
    @FocusState private var focusedChannelID: String?
    @State private var backgroundChannelID = LiveChannel.all.first?.id
    @Namespace private var channelFocusScope
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.resetFocus) private var resetFocus

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IoDesign.shelfGap) {
                VStack(alignment: .leading, spacing: IoDesign.shelfGap) {
                    Text("Io").font(IoDesign.pageTitle)
                    VStack(alignment: .leading, spacing: IoDesign.sectionHeadingGap) {
                        Text("Vaata otse").font(IoDesign.sectionTitle)
                        HStack(spacing: IoDesign.cardGap) {
                            ForEach(LiveChannel.all) { channel in
                                Button { selectedChannel = channel } label: {
                                    LiveChannelCard(channel: channel)
                                }
                                .buttonStyle(.card)
                                .accessibilityIdentifier("live-channel-\(channel.id)")
                                .focused($focusedChannelID, equals: channel.id)
                                .prefersDefaultFocus(channel.id == backgroundChannelID, in: channelFocusScope)
                            }
                        }
                    }
                }
                .padding(.horizontal, IoDesign.contentInset)

                if !favorites.entries.isEmpty {
                    ProgrammeRow(title: "Lemmikud", items: favorites.entries.map(\.programme), openProgramme: openProgramme)
                        .task { await favorites.resolveLegacyArtwork() }
                }

                if !history.inProgress.isEmpty {
                    ProgrammeRow(title: "Jätka vaatamist", items: history.inProgress.prefix(7).map(\.programme), allowsRemovingProgress: true, openProgramme: openProgramme)
                }

            }
            .padding(.vertical, IoDesign.focusRoom)
        }
        .scrollClipDisabled()
        .ignoresSafeArea(.container, edges: .horizontal)
        .focusScope(channelFocusScope)
        .onAppear {
            focusedChannelID = backgroundChannelID
            resetFocus(in: channelFocusScope)
        }
        .onChange(of: focusedChannelID) { _, channelID in
            if let channelID { backgroundChannelID = channelID }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            GeometryReader { geometry in
                ZStack {
                    LinearGradient(colors: [Color(white: 0.12), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                    LiveBackgroundStage(channelID: backgroundChannelID,
                                        size: geometry.size,
                                        isActive: selectedChannel == nil && scenePhase == .active)
                }
                // A stationary layer above all moving videos and below the browsing UI.
                .overlay {
                    LinearGradient(
                        colors: [.black.opacity(0.92), .black.opacity(0.16)],
                        startPoint: .topLeading,
                        endPoint: UnitPoint(x: geometry.size.height / max(geometry.size.width, 1), y: 1)
                    )
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .fullScreenCover(item: $selectedChannel, onDismiss: {
            focusedChannelID = backgroundChannelID
        }) { channel in
            LivePlayerScreen(channel: channel)
        }
    }
}
