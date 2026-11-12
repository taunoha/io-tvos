import SwiftUI

extension View {
    func programmeDetailDestination(_ programme: Binding<Programme?>) -> some View {
        navigationDestination(isPresented: Binding(
            get: { programme.wrappedValue != nil },
            set: { if !$0 { programme.wrappedValue = nil } }
        )) {
            if let detail = programme.wrappedValue {
                ProgrammeDetailView(programme: detail)
            }
        }
    }
}

struct ProgrammeDetailView: View {
    private struct DetailRequest: Equatable {
        var seasonID: Int?
        var retry = 0
    }

    @Environment(ProgrammeFavorites.self) private var favorites
    @Environment(WatchHistory.self) private var history
    @Environment(\.openProgrammeDetail) private var openProgramme
    let programme: Programme
    @State private var page: ProgrammeDetail?
    @State private var seasons: [ProgrammeDetail.SeasonChoice] = []
    @State private var selectedSeasonID: Int?
    @State private var request = DetailRequest()
    @State private var loading = true
    @State private var error: String?
    @State private var playing: PlaybackSelection?
    @State private var programmeToOpen: Programme?
    @State private var openedEpisodeID: Int?
    @State private var restoredEpisodeFocusID: Int?
    @FocusState private var focusedSeasonID: Int?

    init(programme: Programme) {
        self.programme = programme
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: IoDesign.shelfGap) {
                if page == nil {
                    loadStatus
                }
                if let page {
                    HStack(alignment: .top, spacing: IoDesign.Space.xxLarge) {
                        VStack(alignment: .leading, spacing: IoDesign.Space.large) {
                            VStack(alignment: .leading, spacing: IoDesign.sectionHeadingGap) {
                                Text(page.mainContent.rootContent?.heading ?? programme.heading).font(IoDesign.pageTitle)
                                if page.mainContent.heading != programme.heading { Text(page.mainContent.heading).font(IoDesign.sectionTitle) }
                                if !page.mainContent.episodeLabel.isEmpty { Text(page.mainContent.episodeLabel).font(IoDesign.metadata).foregroundStyle(.secondary) }
                            }
                            Text(page.mainContent.descriptionText).font(IoDesign.body).lineLimit(6).foregroundStyle(.secondary)
                            if programme.source == .lasteekraan && !page.mainContent.hasVideo {
                                Text(String(localized: "detail.unavailable")).font(IoDesign.body).foregroundStyle(.secondary)
                            } else if let saved = history.entry(for: page.mainContent.id) {
                                HStack(spacing: IoDesign.Space.large) {
                                    Button { playing = PlaybackSelection(programme: page.mainContent, position: saved.position) } label: { Label(String(localized: "detail.resume", defaultValue: "Jätka · \(saved.positionLabel)"), systemImage: "play.fill") }
                                    Button(String(localized: "detail.restart")) {
                                        history.remove(page.mainContent.id)
                                        playing = PlaybackSelection(programme: page.mainContent, position: 0)
                                    }
                                }
                            } else {
                                Button { playing = PlaybackSelection(programme: page.mainContent, position: 0) } label: { Label(String(localized: "detail.play"), systemImage: "play.fill") }
                            }
                            if let favorite = ProgrammeFavorite(programme: programme, mainContent: page.mainContent) {
                                let isFavorite = favorites.contains(favorite)
                                Button(isFavorite ? String(localized: "detail.removeFavorite") : String(localized: "detail.addFavorite"),
                                       systemImage: isFavorite ? "star.fill" : "star") {
                                    favorites.toggle(favorite)
                                }
                            }
                            if history.entry(for: page.mainContent.id) != nil {
                                Button(String(localized: "action.removeProgress"), systemImage: "trash") {
                                    history.remove(page.mainContent.id)
                                }
                                .font(IoDesign.metadata)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        ProgrammeArtwork(url: page.mainContent.imageURL) { Color.white.opacity(0.06) }
                            .frame(width: 600, height: 338).clipped().clipShape(RoundedRectangle(cornerRadius: 20))
                    }.padding(.horizontal, IoDesign.contentInset)
                    .ioFullWidthFocusSection()
                    if seasons.count > 1 {
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: IoDesign.Space.large) {
                                ForEach(seasons) { season in
                                    let isSelected = season.id == selectedSeasonID
                                    Button {
                                        if request.seasonID == season.id {
                                            if error != nil { request.retry += 1 }
                                        } else if !isSelected || request.seasonID != nil {
                                            request = DetailRequest(seasonID: season.id)
                                        }
                                    } label: {
                                        IoSelectionPillLabel(title: season.title, isSelected: isSelected, isFocused: focusedSeasonID == season.id)
                                    }
                                    .ioCustomButtonFocus()
                                    .focused($focusedSeasonID, equals: season.id)
                                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                                }
                            }.padding(.horizontal, IoDesign.contentInset).padding(.vertical, IoDesign.focusRoom)
                        }
                        .scrollClipDisabled()
                        .ioFullWidthFocusSection()
                    }
                    if error != nil { loadStatus }
                    let episodes = page.episodes(for: selectedSeasonID)
                    if loading || !episodes.isEmpty {
                        ProgrammeRow(title: String(localized: "detail.episodes"), items: episodes, showsSeriesTitle: false, isLoading: loading, restoredFocusID: restoredEpisodeFocusID, playEpisode: { episode in
                            restoredEpisodeFocusID = nil
                            openedEpisodeID = episode.id
                            playing = PlaybackSelection(programme: episode, position: history.entry(for: episode.id)?.position ?? 0)
                        })
                    }
                }
            }.padding(.vertical, IoDesign.focusRoom)
        }
        .scrollClipDisabled()
        .ignoresSafeArea(.container, edges: .horizontal)
        .task(id: request) { [request] in
            if page != nil, request.seasonID == nil || request.seasonID == selectedSeasonID {
                loading = false
                error = nil
                return
            }
            loading = true
            error = nil
            do {
                let result = try await OnDemandAPI.detail(request.seasonID ?? programme.id, source: programme.source)
                try Task.checkCancellation()
                guard request == self.request else { return }
                // Keep the season buttons stable while detail responses replace the episode data.
                if page == nil { seasons = result.seasons }
                let seasonID = request.seasonID ?? result.currentSeasonID
                if seasonID != selectedSeasonID { restoredEpisodeFocusID = nil }
                selectedSeasonID = seasonID
                page = result
                loading = false
            } catch {
                guard !Task.isCancelled, request == self.request else { return }
                self.error = page == nil ? String(localized: "detail.loadFailed") :
                    String(localized: "detail.seasonLoadFailed")
                loading = false
            }
        }
        .fullScreenCover(item: $playing, onDismiss: {
            restoredEpisodeFocusID = openedEpisodeID
            openedEpisodeID = nil
            if let programmeToOpen {
                self.programmeToOpen = nil
                if programmeToOpen.id != programme.id || programmeToOpen.source != programme.source {
                    openProgramme(programmeToOpen)
                }
            }
        }) { selection in
            OnDemandPlayerScreen(
                programme: selection.programme,
                startPosition: selection.position,
                history: history
            ) {
                programmeToOpen = programme.type == "series" ? programme : selection.programme.playbackDetailProgramme
            }
        }
    }

    @ViewBuilder
    private var loadStatus: some View {
        if loading {
            ProgressView(String(localized: "detail.loading"))
                .padding(.horizontal, IoDesign.contentInset)
                .padding(.vertical, IoDesign.focusRoom)
        } else if let error {
            LoadFailureView(message: error) { request.retry += 1 }
                .padding(.horizontal, IoDesign.contentInset)
                .padding(.vertical, IoDesign.focusRoom)
        }
    }
}
