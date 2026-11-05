import SwiftUI
import AVKit

struct PlaybackSelection: Identifiable {
    let id = UUID()
    let programme: Programme
    let position: Double
}

struct OnDemandPlayerScreen: View {
    let programme: Programme
    let startPosition: Double
    let history: WatchHistory
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback: OnDemandPlayback

    init(programme: Programme, startPosition: Double, history: WatchHistory) {
        self.programme = programme
        self.startPosition = startPosition
        self.history = history
        _playback = StateObject(wrappedValue: OnDemandPlayback(history: history))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player = playback.player {
                NativePlayer(player: player, onDismiss: { dismiss() }) {
                    VStack(alignment: .leading, spacing: IoDesign.playerInfoRowSpacing) {
                        Text(programme.playbackTitle).font(.title2.bold())
                        if let episodeTitle = programme.playbackSubtitle {
                            Text(episodeTitle).foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                    .lineLimit(1)
                    .playerInfoCard()
                }
                .ignoresSafeArea()
            }
            if let error = playback.error {
                VStack(spacing: 30) {
                    Text(programme.heading).font(.largeTitle.bold())
                    Text(error).font(.title3).multilineTextAlignment(.center).frame(maxWidth: 1100)
                    HStack(spacing: 30) {
                        Button("Proovi uuesti") { playback.start(programme, position: history.entry(for: programme.id)?.position ?? startPosition) }
                        Button("Tagasi saate juurde") { dismiss() }
                    }
                }
            } else if playback.loading {
                ProgressView("Laadin videot…").padding(40).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 20)).allowsHitTesting(false)
            }
        }
        .onAppear { playback.start(programme, position: history.entry(for: programme.id)?.position ?? startPosition) }
        .onChange(of: playback.didFinish) { _, finished in
            if finished { dismiss() }
        }
        .onDisappear { playback.stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { playback.saveProgress() } }
        .onExitCommand { dismiss() }
    }
}
