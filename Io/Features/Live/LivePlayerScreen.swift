import SwiftUI
import AVKit

private struct LivePlayerInfo: View {
    let channel: LiveChannel
    let player: AVPlayer
    let onOpenProgramme: (Programme) -> Void
    @State private var schedules: [TelekavaEntry] = []
    @State private var programme: Programme?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let date = player.currentItem?.currentDate() ?? context.date
            let day = TelekavaAPI.day(containing: date)
            let current = schedules.first { $0.isCurrent(at: date) }
            let contentID = current?.contentId

            Group {
                if let current {
                    let status = current.isCurrent(at: context.date) ? " · Praegu eetris" : ""
                    let currentProgramme = programme?.id == contentID ? programme : nil
                    ProgrammeInfoCard(title: current.title,
                                      metadata: "\(current.timeRange) · \(channel.title)\(status)",
                                      lead: current.lead,
                                      programme: currentProgramme,
                                      onOpenProgramme: currentProgramme.map { programme in
                                          { onOpenProgramme(programme.playbackDetailProgramme) }
                                      })
                } else {
                    ProgrammeInfoCard(title: channel.title, metadata: "Saatekava pole saadaval")
                }
            }
            .task(id: day) {
                while !Task.isCancelled {
                    await loadSchedule(for: day, at: date)
                    try? await Task.sleep(for: .seconds(300))
                }
            }
            .task(id: contentID) {
                programme = nil
                guard let contentID,
                      let page = try? await OnDemandAPI.detail(contentID),
                      !Task.isCancelled else { return }
                programme = page.mainContent
            }
        }
    }

    private func loadSchedule(for day: Date, at date: Date) async {
        guard var entries = try? await TelekavaAPI.schedule(channel: channel, day: day) else { return }
        if !entries.contains(where: { $0.isCurrent(at: date) }),
           let overnight = try? await TelekavaAPI.schedule(channel: channel, day: TelekavaAPI.day(-1, from: day)) {
            // ERR may list programmes after midnight under the previous broadcast day.
            let ids = Set(entries.map(\.id))
            entries += overnight.filter { $0.endTime > day.timeIntervalSince1970 && !ids.contains($0.id) }
        }
        guard !Task.isCancelled else { return }
        schedules = entries
    }
}

struct LivePlayerScreen: View {
    let channel: LiveChannel
    let onOpenProgramme: (Programme) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LiveChannel.lastWatchedKey) private var lastChannelID = "etv"
    @StateObject private var playback = LivePlayback()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player = playback.player {
                NativePlayer(player: player, onDismiss: { dismiss() }) {
                    LivePlayerInfo(channel: channel, player: player) { programme in
                        onOpenProgramme(programme)
                        dismiss()
                    }
                }
                .ignoresSafeArea()
            }
            if let error = playback.errorMessage {
                VStack(spacing: IoDesign.shelfGap) {
                    VStack(spacing: IoDesign.sectionHeadingGap) {
                        Text(channel.title).font(IoDesign.pageTitle)
                        Text(error).font(IoDesign.body).multilineTextAlignment(.center).frame(maxWidth: 1000)
                    }
                    HStack(spacing: IoDesign.Space.xLarge) {
                        Button("Proovi uuesti") { playback.start(channel) }
                        Button("Tagasi kanalite juurde") { dismiss() }
                    }
                }
            } else if playback.isLoading {
                VStack(spacing: IoDesign.Space.large) {
                    ProgressView()
                    Text(channel.title).font(IoDesign.sectionTitle.weight(.bold))
                    Text(playback.message).foregroundStyle(.secondary)
                }
                .padding(IoDesign.Space.xLarge)
                .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 24))
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            lastChannelID = channel.id
            playback.start(channel)
        }
        .onDisappear { playback.stop() }
        .onExitCommand { dismiss() }
    }
}
