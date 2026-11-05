import SwiftUI
import AVKit

/// Owns both streams until the incoming layer has decoded its first frame.
@MainActor
private final class LiveBackgroundPlayback: ObservableObject {
    @MainActor
    struct Entry: Identifiable {
        let id = UUID()
        let channel: LiveChannel
        let playback = LivePlayback(isMuted: true)
        let direction: CGFloat
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var currentID: UUID?
    @Published private(set) var pendingID: UUID?
    private var timeout: Task<Void, Never>?
    private var cleanup: Task<Void, Never>?

    func request(_ channelID: String?) {
        timeout?.cancel()
        cleanup?.cancel()
        // Discard superseded loads and completed outgoing backgrounds.
        remove { $0.id != currentID }
        pendingID = nil
        guard let channel = LiveChannel.all.first(where: { $0.id == channelID }) else {
            stop()
            return
        }
        let current = entries.first { $0.id == currentID }
        guard current?.channel.id != channelID else { return }
        let previousIndex = LiveChannel.all.firstIndex { $0.id == current?.channel.id } ?? 0
        let nextIndex = LiveChannel.all.firstIndex { $0.id == channelID } ?? 0
        let entry = Entry(channel: channel, direction: nextIndex >= previousIndex ? 1 : -1)
        entries.append(entry)
        pendingID = entry.id
        entry.playback.start(channel)
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard let self, self.pendingID == entry.id else { return }
            // Never leave the previous channel displayed indefinitely under a new selection.
            self.stop()
        }
    }

    func ready(_ id: UUID, player: AVPlayer, reduceMotion: Bool) {
        guard pendingID == id,
              let incoming = entries.first(where: { $0.id == id }),
              incoming.playback.player === player else { return }
        timeout?.cancel()
        let hadCurrent = currentID != nil
        let animation: Animation? = hadCurrent && !reduceMotion
            ? .timingCurve(0.16, 1, 0.3, 1, duration: 0.9) : nil
        withAnimation(animation) {
            currentID = id
            pendingID = nil
        }
        cleanup = Task { [weak self] in
            if animation != nil {
                do { try await Task.sleep(for: .milliseconds(950)) } catch { return }
            }
            guard let self, self.currentID == id else { return }
            self.remove { $0.id != id }
        }
    }

    func stop() {
        timeout?.cancel()
        cleanup?.cancel()
        remove { _ in true }
        currentID = nil
        pendingID = nil
    }

    private func remove(where shouldRemove: (Entry) -> Bool) {
        for entry in entries where shouldRemove(entry) { entry.playback.stop() }
        entries.removeAll(where: shouldRemove)
    }
}

struct LiveBackgroundStage: View {
    let channelID: String?
    let size: CGSize
    let isActive: Bool
    @StateObject private var backgrounds = LiveBackgroundPlayback()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(Array(backgrounds.entries.enumerated()), id: \.element.id) { index, entry in
                LiveChannelBackground(playback: entry.playback, size: size) { player in
                    backgrounds.ready(entry.id, player: player, reduceMotion: reduceMotion)
                }
                .offset(x: offset(for: entry))
                // Entries are appended in selection order, so the incoming stream is on top.
                .zIndex(Double(index))
                .transition(.identity)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .task(id: "\(channelID ?? "")-\(isActive)") {
            if isActive { backgrounds.request(channelID) }
            else { backgrounds.stop() }
        }
        .onDisappear { backgrounds.stop() }
    }

    private func offset(for entry: LiveBackgroundPlayback.Entry) -> CGFloat {
        if entry.id == backgrounds.currentID { return 0 }
        if entry.id == backgrounds.pendingID { return entry.direction * size.width }
        let direction = backgrounds.entries.first { $0.id == backgrounds.currentID }?.direction ?? 1
        return -direction * size.width
    }
}

private struct LiveChannelBackground: View {
    @ObservedObject var playback: LivePlayback
    let size: CGSize
    let onReady: (AVPlayer) -> Void

    var body: some View {
        ZStack {
            if let player = playback.player {
                LiveBackgroundVideo(player: player, onReady: { onReady(player) })
                    .id(ObjectIdentifier(player))
                    .transition(.identity)
            }
        }
        .frame(width: size.width + 120, height: size.height + 120)
        .clipped()
        .blur(radius: 20, opaque: true)
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

private struct LiveBackgroundVideo: UIViewRepresentable {
    let player: AVPlayer
    let onReady: () -> Void

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
        let onReady = onReady
        context.coordinator.observation = view.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async { onReady() }
        }
        return view
    }

    func updateUIView(_ view: VideoView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    static func dismantleUIView(_ view: VideoView, coordinator: Coordinator) {
        coordinator.observation?.invalidate()
        view.playerLayer.player = nil
    }
}
