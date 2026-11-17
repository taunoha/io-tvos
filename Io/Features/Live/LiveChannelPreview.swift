import AVKit
import SwiftUI

struct LiveChannelPreview: View {
    let channel: LiveChannel
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var playback = LivePlayback(isMuted: true)
    @State private var readyPlayerID: ObjectIdentifier?

    var body: some View {
        Color.clear.overlay {
            if isActive, let player = playback.player {
                let playerID = ObjectIdentifier(player)
                let isReady = readyPlayerID == playerID
                LivePreviewVideo(player: player) {
                    readyPlayerID = playerID
                }
                .id(playerID)
                .overlay {
                    LinearGradient(stops: [.init(color: .black.opacity(0.91), location: 0),
                                           .init(color: .black.opacity(0.72), location: 0.49),
                                           .init(color: .black.opacity(0.10), location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                }
                .opacity(isReady ? 1 : 0)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: isReady)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: isActive) { _, active in
            if !active { stop() }
        }
        .task(id: isActive) {
            guard isActive else { return }
            // Let quick remote moves settle before opening a live stream.
            do {
                try await Task.sleep(for: .milliseconds(350))
                try Task.checkCancellation()
                playback.start(channel)
            } catch {
                return
            }
        }
        .onDisappear { stop() }
    }

    private func stop() {
        readyPlayerID = nil
        playback.stop()
    }
}

private struct LivePreviewVideo: UIViewRepresentable {
    let player: AVPlayer
    let onReady: @MainActor () -> Void

    final class VideoView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    final class Coordinator {
        var observation: NSKeyValueObservation?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> VideoView {
        let view = VideoView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        context.coordinator.observation = view.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak view] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async { [weak view] in
                guard view?.playerLayer.player === player else { return }
                onReady()
            }
        }
        return view
    }

    func updateUIView(_ view: VideoView, context: Context) {}

    static func dismantleUIView(_ view: VideoView, coordinator: Coordinator) {
        coordinator.observation?.invalidate()
        view.playerLayer.player = nil
    }
}
