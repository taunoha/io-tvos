import AVKit
import Combine

@MainActor
final class OnDemandPlayback: ObservableObject {
    private let history: WatchHistory

    init(history: WatchHistory) {
        self.history = history
    }

    @Published private(set) var didFinish = false
    @Published private(set) var player: AVPlayer?
    @Published private(set) var error: String?
    @Published private(set) var loading = true
    private var loadTask: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var statusObservation: NSKeyValueObservation?
    private var controlObservation: NSKeyValueObservation?
    private var failureObserver: NSObjectProtocol?
    private var fairPlay: FairPlaySession?
    private var progressObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var programme: Programme?
    private var initialPosition = 0.0
    private var initialSeekCompleted = false
    private var initialSeekStarted = false
    private var hasPlayed = false
    private var generation = UUID()

    func start(_ programme: Programme, position: Double = 0) {
        stop(); error = nil; loading = true
        self.programme = programme
        self.initialPosition = position.isFinite ? max(0, position) : 0
        self.initialSeekCompleted = self.initialPosition <= 0
        self.initialSeekStarted = false
        self.hasPlayed = false
        let id = programme.id
        let token = generation
        loadTask = Task { [weak self] in
            do {
                let source = try await OnDemandAPI.playbackSource(id, source: programme.source)
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                try self.install(source, token: token)
            } catch is CancellationError { }
            catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.fail((error as? FairPlayFailure)?.localizedDescription ?? (error as? OnDemandError)?.localizedDescription ?? String(localized: "player.onDemand.error.loadFailed"))
            }
        }
    }
    private func install(_ source: PlaybackSource, token: UUID) throws {
        let asset = AVURLAsset(url: source.url)
        if let configuration = source.fairPlay {
            fairPlay = try FairPlaySession(configuration: configuration, asset: asset) { [weak self] message in
                guard let self, self.generation == token else { return }
                self.fail(message)
            }
        }
        let item = AVPlayerItem(asset: asset)
        if let programme {
            var metadata = [titleMetadata(.commonIdentifierTitle, programme.playbackTitle)]
            if let subtitle = programme.playbackSubtitle {
                metadata.append(titleMetadata(.iTunesMetadataTrackSubTitle, subtitle))
            }
            item.externalMetadata = metadata
        }
        let player = AVPlayer(playerItem: item)
        self.player = player
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                if status == .failed { self.fail(String(localized: "player.onDemand.error.unplayable")) }
                else if status == .readyToPlay, !self.initialSeekCompleted, !self.initialSeekStarted, let player = self.player {
                    self.initialSeekStarted = true
                    player.pause()
                    let duration = item.duration.seconds
                    let position = duration.isFinite && duration > 0 ? min(self.initialPosition, max(0, duration - 1)) : self.initialPosition
                    player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                        Task { @MainActor [weak self] in
                            guard let self, self.generation == token else { return }
                            if finished {
                                self.initialSeekCompleted = true
                                self.player?.play()
                            } else { self.fail(String(localized: "player.onDemand.error.resumeFailed")) }
                        }
                    }
                }
            }
        }
        controlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.loading = !self.initialSeekCompleted || status == .waitingToPlayAtSpecifiedRate
                if status == .playing && self.initialSeekCompleted { self.hasPlayed = true }
                if status == .paused { self.saveProgress() }
                self.timeout?.cancel(); self.timeout = nil
                if self.loading { self.armTimeout(token) }
            }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.fail(String(localized: "player.onDemand.error.interrupted"))
            }
        }
        progressObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 10, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.saveProgress()
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.saveProgress(ended: true)
                self.didFinish = true
            }
        }
        armTimeout(token)
        player.play() // Preparation triggers readyToPlay; a saved position is applied there before history updates.
    }

    private func titleMetadata(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item
    }

    func saveProgress(ended: Bool = false) {
        guard !didFinish, hasPlayed, initialSeekCompleted, let programme, let player, let item = player.currentItem,
              item.status == .readyToPlay else { return }
        history.save(programme, position: player.currentTime().seconds, duration: item.duration.seconds, ended: ended)
    }
    private func armTimeout(_ token: UUID) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, self.generation == token, self.loading else { return }
            self.fail(String(localized: "player.onDemand.error.timeout"))
        }
    }
    private func fail(_ message: String) { stop(); loading = false; error = message }
    func stop() {
        saveProgress()
        generation = UUID()
        loadTask?.cancel(); loadTask = nil
        timeout?.cancel(); timeout = nil
        statusObservation?.invalidate(); statusObservation = nil
        controlObservation?.invalidate(); controlObservation = nil
        if let observer = failureObserver { NotificationCenter.default.removeObserver(observer) }; failureObserver = nil
        if let observer = endObserver { NotificationCenter.default.removeObserver(observer) }; endObserver = nil
        if let observer = progressObserver { player?.removeTimeObserver(observer) }; progressObserver = nil
        player?.pause(); player?.replaceCurrentItem(with: nil); player = nil
        fairPlay?.stop(); fairPlay = nil
        programme = nil
        hasPlayed = false
    }
}
