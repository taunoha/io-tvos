import SwiftUI
import AVKit

private struct LivePlayerInfo: View {
    let channel: LiveChannel
    let player: AVPlayer
    @State private var schedules: [LiveSchedule] = []

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let date = player.currentItem?.currentDate() ?? context.date
            let previous = schedules.last { $0.endTime <= date.timeIntervalSince1970 }
            let current = schedules.first { $0.contains(date) }
            let next = schedules.first { $0.startTime > date.timeIntervalSince1970 }
            VStack(alignment: .leading, spacing: IoDesign.playerInfoRowSpacing) {
                Text(channel.title).font(IoDesign.sectionTitle.weight(.bold))
                if let previous {
                    scheduleRow(previous, label: "Eelmine")
                }
                if let current {
                    scheduleRow(current, label: "Praegu", isCurrent: true)
                } else {
                    Text("Saatekava pole saadaval")
                }
                if let next {
                    scheduleRow(next, label: "Järgmine")
                }
            }
            .font(IoDesign.body)
            .lineLimit(1)
            .playerInfoCard()
        }
        .task(id: channel.id) {
            while !Task.isCancelled {
                if let result = try? await LiveAPI.schedules(channel), !Task.isCancelled {
                    schedules = result.sorted { $0.startTime < $1.startTime }
                }
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    private func scheduleRow(_ schedule: LiveSchedule, label: String, isCurrent: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: IoDesign.playerInfoColumnSpacing) {
            Image(systemName: isCurrent ? "circle.fill" : "circle")
                .font(IoDesign.inlineIcon)
                .foregroundStyle(isCurrent ? .primary : .secondary)
                .frame(width: IoDesign.playerInfoMarkerWidth)
                .accessibilityHidden(true)
            Text(label)
                .font(IoDesign.caption.weight(isCurrent ? .semibold : .regular))
                .frame(width: IoDesign.playerInfoLabelWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: IoDesign.playerInfoTimeSpacing) {
                Text(schedule.title)
                    .fontWeight(isCurrent ? .semibold : .regular)
                Text(schedule.timeRange)
                    .font(IoDesign.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct LivePlayerScreen: View {
    let channel: LiveChannel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LiveChannel.lastWatchedKey) private var lastChannelID = "etv"
    @StateObject private var playback = LivePlayback()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player = playback.player {
                NativePlayer(player: player, onDismiss: { dismiss() }, infoHeight: IoDesign.playerInfoLiveHeight) {
                    LivePlayerInfo(channel: channel, player: player)
                }
                .ignoresSafeArea()
            }
            if let error = playback.errorMessage {
                VStack(spacing: IoDesign.Space.xLarge) {
                    Text(channel.title).font(IoDesign.pageTitle)
                    Text(error).font(IoDesign.body).multilineTextAlignment(.center).frame(maxWidth: 1000)
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
