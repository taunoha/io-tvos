import SwiftUI
import AVKit

struct PlaybackSelection: Identifiable {
    let id = UUID()
    let programme: Programme
    let position: Double
    var startsOver = false
}

struct OnDemandPlayerScreen: View {
    let programme: Programme
    let startPosition: Double
    let history: WatchHistory
    let startsOver: Bool
    let onOpenProgramme: (Programme) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var selectedEpisode: Programme?
    @StateObject private var playback: OnDemandPlayback

    init(programme: Programme, startPosition: Double, history: WatchHistory, startsOver: Bool = false,
         onOpenProgramme: @escaping (Programme) -> Void) {
        self.programme = programme
        self.startPosition = startPosition
        self.history = history
        self.startsOver = startsOver
        self.onOpenProgramme = onOpenProgramme
        _playback = StateObject(wrappedValue: OnDemandPlayback(history: history))
    }

    private var playbackStartPosition: Double {
        if let selectedEpisode { return history.entry(for: selectedEpisode.id)?.position ?? 0 }
        return startsOver ? 0 : history.entry(for: programme.id)?.position ?? startPosition
    }

    var body: some View {
        let selection = selectedEpisode ?? programme
        let current = playback.detail?.mainContent ?? selection
        ZStack {
            Color.black.ignoresSafeArea()
            if let player = playback.player {
                NativePlayer(player: player, onDismiss: { dismiss() }, additionalTab: episodeTab(for: current)) {
                    ProgrammeInfoCard(title: current.playbackTitle,
                                      metadata: current.playbackSubtitle,
                                      programme: current) {
                        ProgrammeInfoButton {
                            playback.saveProgress()
                            onOpenProgramme(current.playbackDetailProgramme)
                            dismiss()
                        }
                    }
                }
                .id(current.id)
                .ignoresSafeArea()
            }
            if let error = playback.error {
                VStack(spacing: IoDesign.shelfGap) {
                    VStack(spacing: IoDesign.sectionHeadingGap) {
                        Text(selection.heading).font(IoDesign.pageTitle)
                        Text(error).font(IoDesign.body).multilineTextAlignment(.center).frame(maxWidth: 1100)
                    }
                    HStack(spacing: IoDesign.Space.xLarge) {
                        Button(String(localized: "action.retry")) { playback.start(selection, position: playbackStartPosition) }
                        Button(String(localized: "player.onDemand.back")) { dismiss() }
                    }
                }
            } else if playback.loading {
                ProgressView(String(localized: "player.onDemand.loading")).padding(IoDesign.Space.xLarge).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 20)).allowsHitTesting(false)
            }
        }
        .onAppear { playback.start(selection, position: playbackStartPosition) }
        .onChange(of: playback.didFinish) { _, finished in
            if finished { dismiss() }
        }
        .onDisappear { playback.stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { playback.saveProgress() } }
        .onExitCommand { dismiss() }
    }

    private func episodeTab(for current: Programme) -> NativePlayerTab? {
        guard current.type == "episode", let detail = playback.detail,
              let season = detail.season(containingEpisodeID: current.id) else { return nil }
        let episodes = detail.episodes(for: season.id)
        return NativePlayerTab(
            title: String(localized: "player.onDemand.episodesTab"),
            height: IoDesign.playerProgrammeShelfHeight
        ) { closePanel in
            AnyView(PlayerEpisodeShelf(episodes: episodes, currentID: current.id,
                                      seriesTitle: current.rootContent?.heading) { episode in
                guard episode.id != current.id else { return }
                closePanel {
                    guard playback.detail?.mainContent.id == current.id else { return }
                    selectedEpisode = episode
                    playback.start(episode, position: history.entry(for: episode.id)?.position ?? 0)
                }
            }
            .environment(history)
            .id(current.id))
        }
    }
}

private struct PlayerEpisodeShelf: View {
    let episodes: [Programme]
    let currentID: Int
    let seriesTitle: String?
    let onSelect: (Programme) -> Void
    @State private var scrollPosition: ScrollPosition
    @FocusState private var focusedEpisodeID: Int?

    init(episodes: [Programme], currentID: Int, seriesTitle: String?, onSelect: @escaping (Programme) -> Void) {
        self.episodes = episodes
        self.currentID = currentID
        self.seriesTitle = seriesTitle
        self.onSelect = onSelect
        _scrollPosition = State(initialValue: ScrollPosition(id: currentID, anchor: .center))
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: IoDesign.cardGap) {
                ForEach(episodes) { episode in
                    let isCurrent = episode.id == currentID
                    Button { onSelect(episode) } label: {
                        ProgrammeCard(programme: episode, showsSeriesTitle: false, seriesTitle: seriesTitle,
                                      statusLabel: isCurrent ? String(localized: "player.onDemand.watchingEpisode") : nil)
                    }
                    .buttonStyle(.card)
                    .focused($focusedEpisodeID, equals: episode.id)
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
                    .accessibilityIdentifier("player-episode-\(episode.id)")
                }
            }
            .scrollTargetLayout()
            .padding(IoDesign.focusRoom)
        }
        .scrollPosition($scrollPosition)
        .onChange(of: focusedEpisodeID) { previous, focused in
            // AVKit enters the hosted shelf geometrically from the tab bar.
            if previous == nil, let focused, focused != currentID {
                focusedEpisodeID = currentID
            }
        }
        .scrollClipDisabled()
        .scrollIndicators(.hidden)
    }
}
