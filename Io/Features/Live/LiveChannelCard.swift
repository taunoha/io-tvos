import SwiftUI

struct LiveChannelCard: View {
    let channel: LiveChannel
    let width: CGFloat
    let height: CGFloat
    let isFocused: Bool
    let isPreviewVisible: Bool
    let allowsLivePreview: Bool
    @State private var schedules: [LiveSchedule] = []
    @State private var loaded = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: IoDesign.cardCornerRadius, style: .continuous)
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let current = schedules.first { $0.contains(context.date) }
            let title = current?.title ?? String(localized: loaded ? "live.guideUnavailable" : "live.guideLoading")

            VStack(alignment: .leading, spacing: IoDesign.Space.medium) {
                HStack(spacing: IoDesign.Space.medium) {
                    Text(channel.title).font(IoDesign.cardTitle)
                    if current != nil {
                        HStack(spacing: IoDesign.Space.small) {
                            Circle()
                                .fill(.red)
                                .frame(width: IoDesign.Space.small, height: IoDesign.Space.small)
                                .accessibilityHidden(true)
                            Text(String(localized: "live.home.onAir")).font(IoDesign.badge)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: IoDesign.sectionHeadingGap) {
                    Text(title)
                        .font(IoDesign.pageTitle)
                        .lineLimit(2)
                    if let current {
                        Text(current.timeRange)
                            .font(IoDesign.metadata)
                            .monospacedDigit()
                    }
                }
                IoCardActionLabel(title: String(localized: "live.home.channels"), systemImage: "play.fill")
                    .padding(.horizontal, IoDesign.Space.xLarge)
                    .padding(.vertical, IoDesign.Space.medium)
                    .foregroundStyle(.black)
                    .background(.white, in: Capsule())
            }
            .foregroundStyle(.white)
            .frame(maxWidth: width * 0.55, alignment: .leading)
            .padding(IoDesign.liveCardTextInset)
            .frame(width: width, height: height, alignment: .bottomLeading)
            
            .accessibilityElement(children: .combine)
        }
        .background {
            IoDesign.liveCardBackground
                .overlay {
                    LiveChannelPreview(channel: channel, isCardVisible: isPreviewVisible, isEnabled: allowsLivePreview)
                }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(.white.opacity(isFocused ? 1 : 0), lineWidth: IoDesign.liveCardFocusStroke)
                .allowsHitTesting(false)
        }
        .task {
            while !Task.isCancelled {
                do {
                    let updatedSchedules = try await LiveAPI.schedules(channel)
                    try Task.checkCancellation()
                    schedules = updatedSchedules
                } catch {
                    if Task.isCancelled { return }
                }
                loaded = true
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
            }
        }
    }
}
