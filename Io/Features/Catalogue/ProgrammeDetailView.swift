import SwiftUI

struct ProgrammeDetailView: View {
    @Environment(ProgrammeFavorites.self) private var favorites
    @Environment(WatchHistory.self) private var history
    let programme: Programme
    @State private var page: ProgrammeDetail?
    @State private var requestID: Int
    @State private var refresh = 0
    @State private var loading = true
    @State private var error: String?
    @State private var playing: PlaybackSelection?
    @State private var openedEpisodeID: Int?
    @State private var restoredEpisodeFocusID: Int?
    init(programme: Programme) { self.programme = programme; _requestID = State(initialValue: programme.id) }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: IoDesign.shelfGap) {
                if loading { ProgressView("Laadin saate andmeid…").padding(.horizontal, IoDesign.contentInset).padding(.vertical, IoDesign.focusRoom) }
                if let error { LoadFailureView(message: error) { refresh += 1 }.padding(.horizontal, IoDesign.contentInset).padding(.vertical, IoDesign.focusRoom) }
                if let page, !loading {
                    HStack(alignment: .top, spacing: IoDesign.Space.xxLarge) {
                        VStack(alignment: .leading, spacing: IoDesign.Space.large) {
                            VStack(alignment: .leading, spacing: IoDesign.sectionHeadingGap) {
                                Text(page.mainContent.rootContent?.heading ?? programme.heading).font(IoDesign.pageTitle)
                                if page.mainContent.heading != programme.heading { Text(page.mainContent.heading).font(IoDesign.sectionTitle) }
                                if !page.mainContent.episodeLabel.isEmpty { Text(page.mainContent.episodeLabel).font(IoDesign.metadata).foregroundStyle(.secondary) }
                            }
                            Text(page.mainContent.descriptionText).font(IoDesign.body).lineLimit(6).foregroundStyle(.secondary)
                            if programme.source == .lasteekraan && !page.mainContent.hasVideo {
                                Text("Selle sisu video pole praegu kättesaadav.").font(IoDesign.body).foregroundStyle(.secondary)
                            } else if let saved = history.entry(for: page.mainContent.id) {
                                HStack(spacing: IoDesign.Space.large) {
                                    Button { playing = PlaybackSelection(programme: page.mainContent, position: saved.position) } label: { Label("Jätka · " + saved.positionLabel, systemImage: "play.fill") }
                                    Button("Alusta algusest") {
                                        history.remove(page.mainContent.id)
                                        playing = PlaybackSelection(programme: page.mainContent, position: 0)
                                    }
                                }
                            } else {
                                Button { playing = PlaybackSelection(programme: page.mainContent, position: 0) } label: { Label("Vaata", systemImage: "play.fill") }
                            }
                            if let favorite = ProgrammeFavorite(programme: programme, mainContent: page.mainContent) {
                                let isFavorite = favorites.contains(favorite)
                                Button(isFavorite ? "Eemalda lemmikutest" : "Lisa lemmikutesse",
                                       systemImage: isFavorite ? "star.fill" : "star") {
                                    favorites.toggle(favorite)
                                }
                            }
                            if history.entry(for: page.mainContent.id) != nil {
                                Button("Eemalda jätkamisest", systemImage: "trash") {
                                    history.remove(page.mainContent.id)
                                }
                                .font(IoDesign.metadata)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        ProgrammeArtwork(url: page.mainContent.imageURL) { Color.white.opacity(0.06) }
                            .frame(width: 600, height: 338).clipped().clipShape(RoundedRectangle(cornerRadius: 20))
                    }.padding(.horizontal, IoDesign.contentInset)
                    if page.seasons.count > 1 {
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: IoDesign.Space.large) {
                                ForEach(page.seasons) { season in
                                    Button(season.title) { requestID = season.id }
                                }
                            }.padding(.horizontal, IoDesign.contentInset).padding(.vertical, IoDesign.focusRoom)
                        }
                        .scrollClipDisabled()
                    }
                    if !page.episodes.isEmpty {
                        ProgrammeRow(title: "Episoodid", items: page.episodes, showsSeriesTitle: false, restoredFocusID: restoredEpisodeFocusID, playEpisode: { episode in
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
        .task(id: "\(requestID)|\(refresh)") {
            loading = true; error = nil
            do { let result = try await OnDemandAPI.detail(requestID, source: programme.source); try Task.checkCancellation(); page = result; loading = false }
            catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = "Saate andmeid ei saanud laadida. Proovi uuesti."; loading = false } }
        }
        .fullScreenCover(item: $playing, onDismiss: {
            restoredEpisodeFocusID = openedEpisodeID
            openedEpisodeID = nil
        }) { selection in
            OnDemandPlayerScreen(
                programme: selection.programme,
                startPosition: selection.position,
                history: history
            )
        }
    }
}
