import SwiftUI

struct ProgrammeInfoCard: View {
    let title: String
    let metadata: String?
    var lead: String? = nil
    var programme: Programme? = nil

    var body: some View {
        let description = Programme.plainDescription(lead)
        let synopsis = description.isEmpty ? (programme?.descriptionText ?? "") : description
        HStack(alignment: .top ,spacing: IoDesign.Space.xLarge) {
            ProgrammeArtwork(url: programme?.imageURL) {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: "tv").font(IoDesign.sectionTitle).foregroundStyle(.secondary)
                }
            }
            .frame(width: IoDesign.scheduleArtworkWidth, height: IoDesign.scheduleArtworkHeight)
            .clipShape(RoundedRectangle(cornerRadius: IoDesign.scheduleGridCornerRadius))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: IoDesign.sectionHeadingGap) {
                Text(title)
                    .font(IoDesign.scheduleDetailTitle)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if let metadata, !metadata.isEmpty {
                    Text(metadata)
                        .font(IoDesign.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !synopsis.isEmpty {
                    Text(synopsis)
                        .font(IoDesign.body)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(IoDesign.Space.large)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: IoDesign.schedulePanelCornerRadius))
    }
}
