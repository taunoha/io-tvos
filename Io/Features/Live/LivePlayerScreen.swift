import SwiftUI
import AVKit

private struct LivePlayerInfo: View {
    let channel: LiveChannel
    let current: TelekavaEntry?
    let isOnAir: Bool
    let onOpenProgramme: (Programme) -> Void
    @State private var programme: Programme?

    var body: some View {
        Group {
            if let current {
                let status = isOnAir ? " · Praegu eetris" : ""
                let currentProgramme = programme?.id == current.contentId ? programme : nil
                ProgrammeInfoCard(title: current.title,
                                  metadata: "\(current.timeRange) · \(channel.title)\(status)",
                                  lead: current.lead,
                                  programme: currentProgramme) {
                    if let currentProgramme {
                        ProgrammeInfoButton {
                            onOpenProgramme(currentProgramme.playbackDetailProgramme)
                        }
                    }
                }
            } else {
                ProgrammeInfoCard(title: channel.title, metadata: "Saatekava pole saadaval")
            }
        }
        .task(id: current?.contentId) {
            programme = nil
            guard let contentID = current?.contentId,
                  let page = try? await OnDemandAPI.detail(contentID), !Task.isCancelled else { return }
            programme = page.mainContent
        }
    }
}

private struct LivePlayerWithSchedule: View {
    let channel: LiveChannel
    let player: AVPlayer
    let onDismiss: () -> Void
    let onOpenProgramme: (Programme) -> Void
    @Environment(WatchHistory.self) private var history
    @State private var schedules: [Date: [TelekavaEntry]] = [:]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let window = LiveSeekWindow(player: player)
            let date = player.currentItem?.currentDate() ?? context.date
            let days = scheduleDays(from: min(window?.earliestDate ?? date, date), through: max(date, context.date))
            let entries = scheduleEntries(for: days)
            let current = entries.first { $0.isCurrent(at: date) }
            let reachable = window.map { window in
                entries.filter { window.seekTime(for: Date(timeIntervalSince1970: $0.startTime)) != nil }
            } ?? []
            let tab = programmeTab(entries: reachable, date: date)
            NativePlayer(player: player, onDismiss: onDismiss, additionalTab: tab) {
                LivePlayerInfo(channel: channel, current: current,
                               isOnAir: current?.isCurrent(at: context.date) == true, onOpenProgramme: onOpenProgramme)
            }
            .task(id: days) {
                while !Task.isCancelled {
                    await refreshSchedule(for: days)
                    try? await Task.sleep(for: .seconds(300))
                }
            }
        }
    }

    private func programmeTab(entries: [TelekavaEntry], date: Date) -> NativePlayerTab? {
        guard !entries.isEmpty else { return nil }
        return NativePlayerTab(title: "Saated", height: IoDesign.playerProgrammeShelfHeight) { onJump in
            AnyView(LiveProgrammeShelf(entries: entries, viewingDate: date, player: player, onJump: onJump)
                .environment(history))
        }
    }

    private func scheduleDays(from start: Date, through end: Date) -> [Date] {
        // ERR may list programmes after midnight under the previous broadcast day.
        let first = TelekavaAPI.day(-1, from: TelekavaAPI.day(containing: start))
        let last = TelekavaAPI.day(containing: end)
        return Array(sequence(first: first) { day in
            day < last ? TelekavaAPI.day(1, from: day) : nil
        }.reversed())
    }

    private func scheduleEntries(for days: [Date]) -> [TelekavaEntry] {
        var ids = Set<Int>()
        return days.flatMap { schedules[$0] ?? [] }.filter { ids.insert($0.id).inserted }
            .sorted { $0.startTime < $1.startTime }
    }

    private func refreshSchedule(for days: [Date]) async {
        schedules = schedules.filter { days.contains($0.key) }
        await withTaskGroup(of: (Date, [TelekavaEntry]?).self) { group in
            for day in days {
                group.addTask { (day, try? await TelekavaAPI.schedule(channel: channel, day: day)) }
            }
            for await (day, entries) in group {
                guard !Task.isCancelled else { return }
                if let entries { schedules[day] = entries }
            }
        }
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
                LivePlayerWithSchedule(channel: channel, player: player, onDismiss: { dismiss() }) { programme in
                    onOpenProgramme(programme)
                    dismiss()
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
