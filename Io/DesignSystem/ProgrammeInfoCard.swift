import SwiftUI

struct ProgrammeInfoCard: View {
    let title: String
    let metadata: String?
    var lead: String? = nil
    var programme: Programme? = nil
    var onOpenProgramme: (() -> Void)? = nil

    var body: some View {
        let description = Programme.plainDescription(lead)
        let synopsis = description.isEmpty ? (programme?.descriptionText ?? "") : description
        HStack(alignment: .top, spacing: IoDesign.Space.xLarge) {
            ProgrammeArtwork(url: programme?.imageURL) {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: "tv").font(IoDesign.sectionTitle).foregroundStyle(.secondary)
                }
            }
            .frame(width: IoDesign.scheduleArtworkWidth, height: IoDesign.scheduleArtworkHeight)
            .clipShape(RoundedRectangle(cornerRadius: IoDesign.scheduleGridCornerRadius))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: IoDesign.Space.medium) {
                VStack(alignment: .leading, spacing: IoDesign.sectionHeadingGap) {
                    Text(title)
                        .font(IoDesign.scheduleDetailTitle)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    if !synopsis.isEmpty {
                        Text(synopsis)
                            .font(IoDesign.body)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(2)
                            .frame(maxWidth: IoDesign.programmeInfoDescriptionMaxWidth, alignment: .leading)
                    }
                }
                if let metadata, !metadata.isEmpty {
                    Text(metadata)
                        .font(IoDesign.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onOpenProgramme {
                Button(action: onOpenProgramme) {
                    Label("Saate info", systemImage: "info.circle")
                        .font(IoDesign.body.weight(.semibold))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("player-programme-info")
                .fixedSize()
                .frame(height: IoDesign.scheduleArtworkHeight)
            }
        }
        .padding(IoDesign.programmeInfoContentInset)
        .glassEffect(in: .rect(cornerRadius: IoDesign.cardCornerRadius))
    }
}
