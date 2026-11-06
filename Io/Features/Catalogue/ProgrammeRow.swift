import SwiftUI

private struct ProgrammeRowKey: Hashable, Identifiable {
    let programme: Programme

    init(_ programme: Programme) { self.programme = programme }

    var id: Self { self }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.programme.id == rhs.programme.id && lhs.programme.source == rhs.programme.source
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(programme.id)
        hasher.combine(programme.source)
    }
}

struct ProgrammeRow: View {
    let title: String
    let items: [Programme]
    var usesPortraitCards = false
    var allowsRemovingProgress = false
    var showsSeriesTitle = true
    var restoredFocusID: Int? = nil
    var openProgramme: ((Programme) -> Void)? = nil
    var playEpisode: ((Programme) -> Void)? = nil
    @Environment(WatchHistory.self) private var history
    @FocusState private var focusedProgramme: ProgrammeRowKey?

    private func removeProgress(for id: Int) {
        let remaining = items.filter { $0.id != id }
        let index = items.firstIndex { $0.id == id } ?? 0
        let next = remaining.dropFirst(index).first ?? remaining.last
        history.remove(id)
        focusedProgramme = next.map(ProgrammeRowKey.init)
    }

    var body: some View {
        let progressIDs = Set(history.records.lazy.filter { $0.isInProgress }.map(\.id))
        let reservesProgressSpace = items.contains { progressIDs.contains($0.id) }

        VStack(alignment: .leading, spacing: IoDesign.sectionHeadingGap) {
            Text(title)
                .font(IoDesign.sectionTitle)
                .padding(.horizontal, IoDesign.contentInset)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: IoDesign.cardGap) {
                    ForEach(items.map(ProgrammeRowKey.init)) { key in
                        let programme = key.programme
                        Group {
                            if let playEpisode, programme.source != .lasteekraan || programme.hasVideo {
                                Button { playEpisode(programme) } label: {
                                    ProgrammeCard(programme: programme, usesPortraitImage: usesPortraitCards, showsSeriesTitle: showsSeriesTitle, reservesProgressSpace: reservesProgressSpace, playsDirectly: true)
                                }
                            } else if let openProgramme {
                                Button { openProgramme(programme) } label: {
                                    ProgrammeCard(programme: programme, usesPortraitImage: usesPortraitCards, showsSeriesTitle: showsSeriesTitle, reservesProgressSpace: reservesProgressSpace)
                                }
                            } else {
                                NavigationLink { ProgrammeDetailView(programme: programme) } label: {
                                    ProgrammeCard(programme: programme, usesPortraitImage: usesPortraitCards, showsSeriesTitle: showsSeriesTitle, reservesProgressSpace: reservesProgressSpace)
                                }
                            }
                        }
                            .buttonStyle(.card)
                            .focused($focusedProgramme, equals: key)
                            .contextMenu {
                                if allowsRemovingProgress {
                                    Button("Eemalda jätkamisest", systemImage: "trash", role: .destructive) {
                                        removeProgress(for: programme.id)
                                    }
                                }
                            }
                    }
                }.padding(.horizontal, IoDesign.contentInset).padding(.vertical, IoDesign.focusRoom)
            }
            // Focused tvOS cards cast shadows beyond the shelf bounds.
            .scrollClipDisabled()
            .onChange(of: restoredFocusID) { _, id in
                focusedProgramme = items.first { $0.id == id }.map(ProgrammeRowKey.init)
            }
        }
    }
}
