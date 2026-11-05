import AVKit
import Combine
import OSLog

@MainActor
final class LivePlayback: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var message = "Küsin kanali esitusandmeid…"
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = true
    private var loadTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var statusObservation: NSKeyValueObservation?
    private var controlObservation: NSKeyValueObservation?
    private var failureObserver: NSObjectProtocol?
    #if DEBUG
    private var diagnosticObservers: [NSObjectProtocol] = []
    #endif
    private var fairPlay: FairPlaySession?
    private var usingFairPlay = false
    private var channel: LiveChannel?
    private var generation = UUID()
    private var retries = 0
    private var waitingSince: Date?
    private var lastMediaTime: Double?
    private var lastProgressAt = Date()
    private var lastProgrammeCheck = Date()
    private var lastDiagnosticAt = Date.distantPast
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Io", category: "Playback")

    private let isMuted: Bool

    init(isMuted: Bool = false) { self.isMuted = isMuted }

    func start(_ channel: LiveChannel) {
        stop()
        self.channel = channel
        retries = 0
        load()
    }

    private func load(preferFairPlay: Bool? = nil) {
        releasePlayback()
        let token = UUID()
        generation = token
        errorMessage = nil
        isLoading = true
        message = retries == 0 ? "Küsin kanali esitusandmeid…" : "Taastan ühendust…"
        guard let channel else { return }
        diagnostic("load")
        logger.info("Loading channel \(channel.id, privacy: .public); retry \(self.retries)")
        loadTask = Task { [weak self] in
            do {
                let source = try await LiveAPI.streamSource(for: channel, preferFairPlay: preferFairPlay)
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                try self.install(source, token: token)
            } catch is CancellationError {
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.fail(error.localizedDescription, retryable: !(error is PlaybackFailure) && !(error is FairPlayFailure))
            }
        }
    }

    private func install(_ source: PlaybackSource, token: UUID) throws {
        let asset = AVURLAsset(url: source.url)
        usingFairPlay = source.fairPlay != nil
        if let configuration = source.fairPlay {
            fairPlay = try FairPlaySession(configuration: configuration, asset: asset) { [weak self] message in
                guard let self, self.generation == token else { return }
                self.fail(message, retryable: false)
            }
        }
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.isMuted = isMuted
        player.automaticallyWaitsToMinimizeStalling = true
        self.player = player
        waitingSince = Date()
        lastProgressAt = Date()
        lastMediaTime = nil
        lastProgrammeCheck = Date()
        message = "Laadin otsepilti…"
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let failed = item.status == .failed
            // Log only numeric codes; AVFoundation descriptions may contain signed URLs.
            let code = (item.error as NSError?)?.code ?? 0
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, failed else { return }
                self.diagnostic("itemFailed", errorCode: code)
                self.logger.error("AVPlayerItem failed; code \(code)")
                self.fail("Otsevoogu ei saanud avada (veakood \(code)). Põhjuseks võib olla võrgu- või sisupiirang.", retryable: false)
            }
        }
        controlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                if status == .playing {
                    self.isLoading = false
                    self.waitingSince = nil
                    self.logger.info("Playback started")
                    self.diagnostic("playing")
                } else if status == .waitingToPlayAtSpecifiedRate {
                    if self.waitingSince == nil { self.waitingSince = Date() }
                    self.isLoading = true
                    self.message = "Puhverdan otsepilti…"
                    self.diagnostic("waiting")
                } else {
                    // A user pause must never trigger automatic recovery.
                    self.waitingSince = nil
                    self.isLoading = false
                    self.lastProgressAt = Date()
                    self.diagnostic("paused")
                }
            }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] notification in
            let code = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError)?.code
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.diagnostic("failedToPlayToEnd", errorCode: code)
                self.fail("Otseesitus katkes. Kui saade on kaitstud, võib vaja olla täiendavat ligipääsu.", retryable: false)
            }
        }
        #if DEBUG
        let events: [(Notification.Name, String)] = [
            (AVPlayerItem.playbackStalledNotification, "stalled"),
            (AVPlayerItem.timeJumpedNotification, "timeJumped"),
            (AVPlayerItem.newErrorLogEntryNotification, "errorLog")
        ]
        diagnosticObservers = events.map { name, event in
            NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.diagnostic(event)
                }
            }
        }
        #endif
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard let self, self.generation == token, let player = self.player else { return }
                if Date().timeIntervalSince(self.lastDiagnosticAt) >= 30 {
                    self.diagnostic("sample")
                }
                if Date().timeIntervalSince(self.lastProgrammeCheck) >= 30, player.timeControlStatus != .paused, let channel = self.channel {
                    self.lastProgrammeCheck = Date()
                    let selectedDate = player.currentItem?.currentDate() ?? Date()
                    if let required = try? await LiveAPI.requiresFairPlay(channel, at: selectedDate) {
                        guard self.generation == token, !Task.isCancelled else { return }
                        if required != self.usingFairPlay {
                            self.diagnostic("protectionChanged")
                            self.load(preferFairPlay: required)
                            return
                        }
                    }
                    guard self.generation == token, !Task.isCancelled else { return }
                }
                if let since = self.waitingSince, Date().timeIntervalSince(since) > 25 {
                    self.diagnostic("waitingTimeout")
                    self.fail("Otsepildi laadimine võttis liiga kaua aega.", retryable: true)
                    return
                }
                if player.timeControlStatus == .playing {
                    let time = player.currentTime().seconds
                    if time.isFinite, let previous = self.lastMediaTime, abs(time - previous) < 0.1 {
                        if Date().timeIntervalSince(self.lastProgressAt) > 25 {
                            self.diagnostic("progressTimeout")
                            self.fail("Otsepilt jäi seisma.", retryable: true)
                            return
                        }
                    } else { self.lastProgressAt = Date() }
                    self.lastMediaTime = time
                } else { self.lastProgressAt = Date() }
            }
        }
        player.play()
    }

    private func fail(_ description: String, retryable: Bool) {
        diagnostic("failure")
        releasePlayback()
        generation = UUID()
        if retryable, retries < 2 {
            retries += 1
            isLoading = true
            message = "Ühendus katkes. Proovin uuesti (\(retries)/2)…"
            let token = generation
            loadTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(2 * (self?.retries ?? 1))) } catch { return }
                guard let self, self.generation == token else { return }
                self.load()
            }
        } else {
            isLoading = false
            errorMessage = description
            logger.error("Playback stopped with an error")
        }
    }

    func stop() {
        generation = UUID()
        releasePlayback()
        diagnostic("stop")
        channel = nil
    }

    private func diagnostic(_ event: String, errorCode: Int? = nil) {
        lastDiagnosticAt = Date()
        #if DEBUG
        PlaybackDiagnostics.shared.record(event: event, channel: channel?.id, player: player,
            preview: isMuted, fairPlay: player == nil ? nil : usingFairPlay, errorCode: errorCode)
        #endif
    }

    private func releasePlayback() {
        loadTask?.cancel()
        loadTask = nil
        watchdog?.cancel()
        watchdog = nil
        statusObservation?.invalidate()
        statusObservation = nil
        controlObservation?.invalidate()
        controlObservation = nil
        if let observer = failureObserver { NotificationCenter.default.removeObserver(observer) }
        failureObserver = nil
        #if DEBUG
        for observer in diagnosticObservers { NotificationCenter.default.removeObserver(observer) }
        diagnosticObservers.removeAll()
        #endif
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        fairPlay?.stop(); fairPlay = nil
        waitingSince = nil
    }
}
