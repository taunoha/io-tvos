import AVKit
import SwiftUI

struct LiveChannelPreview: View {
    private static let fadeDuration = 0.4
    // A darker shade of the blue-gray backdrop beside the carousel.
    private static let gradientTint = Color(red: 0.15, green: 0.17, blue: 0.19)
    // Each sRGB component is 8% lower than the card background.
    private static let gradientStartTint = Color(red: 0.138 * 0.92, green: 0.1564 * 0.92, blue: 0.1748 * 0.92)

    let channel: LiveChannel
    let isCardVisible: Bool
    let isEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var playback = LivePlayback(isMuted: true)
    @State private var readyPlayerID: ObjectIdentifier?

    private var isActive: Bool { isCardVisible && isEnabled }

    var body: some View {
        Color.clear.overlay {
            if let player = playback.player {
                let playerID = ObjectIdentifier(player)
                let isVisible = isActive && readyPlayerID == playerID
                LivePreviewVideo(player: player) {
                    readyPlayerID = playerID
                }
                .id(playerID)
                .opacity(isVisible ? 1 : 0)
                .animation(reduceMotion || !isEnabled ? nil : .easeInOut(duration: Self.fadeDuration),
                           value: isVisible)
            }
        }
        .overlay {
            LinearGradient(stops: [
                .init(color: Self.gradientStartTint.opacity(0.91), location: 0),
                .init(color: Self.gradientTint.opacity(0.72), location: 0.49),
                .init(color: Self.gradientTint.opacity(0.10), location: 1)
            ], startPoint: .leading, endPoint: .trailing)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { stop() }
        }
        .task(id: isActive) {
            guard !Task.isCancelled else { return }
            if isActive {
                // Reuse the stream if the card becomes visible again during its fade-out.
                if playback.player == nil {
                    let startupDelay = reduceMotion ? .zero : Duration.seconds(LiveHomeView.carouselScrollDuration)
                    playback.start(channel, playerStartupDelay: startupDelay)
                }
                return
            }
            if isEnabled, !reduceMotion, readyPlayerID != nil {
                do { try await Task.sleep(for: .seconds(Self.fadeDuration)) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            stop()
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
