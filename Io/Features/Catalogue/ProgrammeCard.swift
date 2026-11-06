import SwiftUI

struct ProgrammeCard: View {
    @Environment(WatchHistory.self) private var history
    let programme: Programme
    var usesPortraitImage = false
    var showsSeriesTitle = true
    var reservesProgressSpace = false
    var playsDirectly = false
    private var cardWidth: CGFloat { usesPortraitImage ? 280 : 360 }
    var body: some View {
        let saved = history.entry(for: programme.id)
        let subtitle = programme.cardSubtitle

        VStack(alignment: .leading, spacing: IoDesign.Space.medium) {
            ProgrammeArtwork(url: usesPortraitImage ? programme.posterURL : (programme.imageURL ?? saved?.programme.imageURL)) {
                Rectangle().fill(.white.opacity(0.08)).overlay(Image(systemName: "play.rectangle").font(IoDesign.pageTitle).foregroundStyle(.secondary))
            }
            .frame(width: cardWidth, height: usesPortraitImage ? 420 : 203).clipped()
            .overlay(alignment: .bottomLeading) {
                if playsDirectly {
                    Image(systemName: history.isCompleted(programme.id) ? "arrow.counterclockwise" : "play.fill")
                        .font(IoDesign.metadata.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.black.opacity(0.75), in: Circle())
                        .padding(IoDesign.Space.medium)
                        .accessibilityHidden(true)
                }
            }
            VStack(alignment: .leading, spacing: IoDesign.Space.xxSmall) {
                // A lazy shelf takes its height from its first card.
                Text(programme.cardTitle(showsSeriesTitle: showsSeriesTitle))
                    .font(IoDesign.cardTitle).lineLimit(2, reservesSpace: true)
                if showsSeriesTitle {
                    Text(subtitle ?? " ")
                        .font(IoDesign.metadata).foregroundStyle(.secondary)
                        .lineLimit(1, reservesSpace: true)
                        .accessibilityHidden(subtitle == nil)
                }
                if reservesProgressSpace {
                    ProgressView(value: saved?.progress ?? 0) {
                        Text(saved?.remainingLabel ?? " ")
                            .font(IoDesign.caption).foregroundStyle(.secondary)
                            .lineLimit(1, reservesSpace: true)
                    }
                    .padding(.top, IoDesign.Space.xSmall)
                    .opacity(saved == nil ? 0 : 1)
                    .accessibilityHidden(saved == nil)
                }
            }
            .frame(width: cardWidth - 2 * IoDesign.Space.large, alignment: .topLeading).padding(.horizontal, IoDesign.Space.large)
        }
        .frame(width: cardWidth).padding(.bottom, IoDesign.Space.large)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .task(id: programme.id) {
            if programme.imageURL == nil {
                await history.restoreImage(for: programme.id)
            }
        }
    }
}
