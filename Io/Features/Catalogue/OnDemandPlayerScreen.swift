import SwiftUI
import AVKit

struct PlaybackSelection: Identifiable {
    let id = UUID()
    let programme: Programme
    let position: Double
    var startsOver = false
}

struct OnDemandPlayerScreen: View {
    let programme: Programme
    let startPosition: Double
    let history: WatchHistory
    let startsOver: Bool
    let onOpenProgramme: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback: OnDemandPlayback

    init(programme: Programme, startPosition: Double, history: WatchHistory, startsOver: Bool = false,
         onOpenProgramme: @escaping () -> Void) {
        self.programme = programme
        self.startPosition = startPosition
        self.history = history
        self.startsOver = startsOver
        self.onOpenProgramme = onOpenProgramme
        _playback = StateObject(wrappedValue: OnDemandPlayback(history: history))
    }

    private var playbackStartPosition: Double {
        startsOver ? 0 : history.entry(for: programme.id)?.position ?? startPosition
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player = playback.player {
                NativePlayer(player: player, onDismiss: { dismiss() }) {
                    ProgrammeInfoCard(title: programme.playbackTitle,
                                      metadata: programme.playbackSubtitle,
                                      programme: programme) {
                        ProgrammeInfoButton {
                            playback.saveProgress()
                            onOpenProgramme()
                            dismiss()
                        }
                    }
                }
                .ignoresSafeArea()
            }
            if let error = playback.error {
                VStack(spacing: IoDesign.shelfGap) {
                    VStack(spacing: IoDesign.sectionHeadingGap) {
                        Text(programme.heading).font(IoDesign.pageTitle)
                        Text(error).font(IoDesign.body).multilineTextAlignment(.center).frame(maxWidth: 1100)
                    }
                    HStack(spacing: IoDesign.Space.xLarge) {
                        Button(String(localized: "action.retry")) { playback.start(programme, position: playbackStartPosition) }
                        Button(String(localized: "player.onDemand.back")) { dismiss() }
                    }
                }
            } else if playback.loading {
                ProgressView(String(localized: "player.onDemand.loading")).padding(IoDesign.Space.xLarge).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 20)).allowsHitTesting(false)
            }
        }
        .onAppear { playback.start(programme, position: playbackStartPosition) }
        .onChange(of: playback.didFinish) { _, finished in
            if finished { dismiss() }
        }
        .onDisappear { playback.stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { playback.saveProgress() } }
        .onExitCommand { dismiss() }
    }
}
