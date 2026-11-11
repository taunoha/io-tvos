import AVKit
import SwiftUI

struct LiveSeekWindow {
    let programmeDate: Date
    let mediaTime: CMTime
    let ranges: [CMTimeRange]

    init?(player: AVPlayer) {
        guard let item = player.currentItem, item.status == .readyToPlay,
              let date = item.currentDate() else { return nil }
        let time = item.currentTime()
        let ranges = item.seekableTimeRanges.map(\.timeRangeValue)
            .filter { $0.isValid && !$0.isEmpty && $0.start.isNumeric && $0.end.isNumeric }
            .sorted { $0.start < $1.start }
        guard time.isNumeric, !ranges.isEmpty else { return nil }
        programmeDate = date
        mediaTime = time
        self.ranges = ranges
    }

    var earliestDate: Date {
        programmeDate.addingTimeInterval((ranges[0].start - mediaTime).seconds)
    }

    // The stream date anchors the wall-clock schedule to the media timeline.
    func seekTime(for date: Date) -> CMTime? {
        let offset = CMTime(seconds: date.timeIntervalSince(programmeDate), preferredTimescale: 600)
        let target = mediaTime + offset
        return ranges.contains { $0.containsTime(target) } ? target : nil
    }
}

struct LiveProgrammeShelf: View {
    let entries: [TelekavaEntry]
    let viewingDate: Date
    let player: AVPlayer
    let onJump: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: IoDesign.cardGap) {
                ForEach(entries) { entry in
                    Button {
                        jump(to: Date(timeIntervalSince1970: entry.startTime))
                    } label: {
                        LiveProgrammeCard(entry: entry, isPlaying: entry.isCurrent(at: viewingDate))
                    }
                    .buttonStyle(.card)
                    .accessibilityHint("Alustab saadet algusest")
                }
            }
            .padding(IoDesign.focusRoom)
        }
        .scrollClipDisabled()
        .scrollIndicators(.hidden)
    }

    private func jump(to date: Date) {
        guard let item = player.currentItem,
              let target = LiveSeekWindow(player: player)?.seekTime(for: date) else { return }
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            guard finished else { return }
            Task { @MainActor in
                guard player.currentItem === item else { return }
                player.play()
                onJump()
            }
        }
    }
}

private struct LiveProgrammeCard: View {
    let entry: TelekavaEntry
    let isPlaying: Bool
    @State private var artworkProgramme: Programme?

    var body: some View {
        let programme = Programme(
            id: entry.contentId ?? entry.id, heading: entry.title, subHeading: nil,
            lead: nil, type: nil, scheduleStart: entry.startTime,
            photos: artworkProgramme?.photos, horizontalPhotos: artworkProgramme?.horizontalPhotos,
            verticalPhotos: artworkProgramme?.verticalPhotos, medias: nil, rootContent: nil
        )
        ProgrammeCard(programme: programme, subtitleOverride: entry.startLabel + (isPlaying ? " · Vaatad" : ""))
            .task(id: entry.contentId) {
                artworkProgramme = nil
                guard let id = entry.contentId,
                      let detail = try? await OnDemandAPI.detail(id), !Task.isCancelled else { return }
                artworkProgramme = detail.mainContent
            }
    }
}
