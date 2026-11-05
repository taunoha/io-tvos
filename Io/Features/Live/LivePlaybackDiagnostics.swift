import AVKit
import Darwin

#if DEBUG
/// Bounded local diagnostics, with no stream URLs, account details or tokens.
@MainActor
final class PlaybackDiagnostics {
    static let shared = PlaybackDiagnostics()
    private struct TimeRange: Codable {
        let start: Double
        let end: Double

        init?(_ value: NSValue) {
            let range = value.timeRangeValue
            start = range.start.seconds
            end = range.end.seconds
            guard start.isFinite, end.isFinite else { return nil }
        }
    }

    private struct Sample: Codable {
        let date: Date
        let event: String
        let channel: String?
        let residentMB: Double?
        let mediaTime: Double?
        let timeControlStatus: Int?
        let activePlayer: Bool
        let session: UUID?
        let preview: Bool?
        let programmeDate: Date?
        let waitingReason: String?
        let bufferEmpty: Bool?
        let likelyToKeepUp: Bool?
        let seekableRanges: [TimeRange]?
        let loadedRanges: [TimeRange]?
        let fairPlay: Bool?
        let errorCode: Int?
        let streamErrorCode: Int?
    }
    private let session = UUID()
    private let fileURL = URL.cachesDirectory.appendingPathComponent("playback-diagnostics.json")
    private var samples: [Sample]

    private init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        samples = (try? decoder.decode([Sample].self, from: Data(contentsOf: fileURL))) ?? []
    }

    func record(event: String, channel: String?, player: AVPlayer?, preview: Bool,
                fairPlay: Bool?, errorCode: Int?) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        let residentMB = result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : nil
        let item = player?.currentItem
        let mediaTime = player?.currentTime().seconds
        samples.append(Sample(date: Date(), event: event, channel: channel, residentMB: residentMB,
            mediaTime: mediaTime.flatMap { $0.isFinite ? $0 : nil },
            timeControlStatus: player?.timeControlStatus.rawValue, activePlayer: player != nil,
            session: session, preview: preview, programmeDate: item?.currentDate(),
            waitingReason: player?.reasonForWaitingToPlay?.rawValue, bufferEmpty: item?.isPlaybackBufferEmpty,
            likelyToKeepUp: item?.isPlaybackLikelyToKeepUp,
            seekableRanges: item?.seekableTimeRanges.compactMap(TimeRange.init),
            loadedRanges: item?.loadedTimeRanges.compactMap(TimeRange.init),
            fairPlay: fairPlay, errorCode: errorCode, streamErrorCode: item?.errorLog()?.events.last?.errorStatusCode))
        if samples.count > 512 { samples.removeFirst(samples.count - 512) }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(samples).write(to: fileURL, options: .atomic)
        } catch { /* Diagnostics must never interrupt playback. */ }
    }
}
#endif
