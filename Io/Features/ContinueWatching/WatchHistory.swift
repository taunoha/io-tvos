import Foundation
import Observation

struct WatchEntry: Codable, Identifiable {
    let id: Int
    var heading: String
    var seriesHeading: String?
    var subtitle: String
    var imageAddress: String?
    var position: Double
    var duration: Double
    var updated: Date
    var catalogueSource: CatalogueSource? = nil
    var completed: Bool
    var programmeType: String? = nil
    var episodeSubHeading: String? = nil
    var scheduleStart: Double? = nil
    var replayDeadline: Date? = nil
    var replayUnavailable: Bool? = nil

    var isInProgress: Bool { !completed && position >= 10 }
    var progress: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }
    var remainingLabel: String {
        let totalMinutes = max(1, Int(ceil((duration - position) / 60)))
        let duration = Duration.seconds(totalMinutes * 60)
        let style: Duration.UnitsFormatStyle = .units(
            allowed: totalMinutes >= 60 ? [.hours, .minutes] : [.minutes],
            width: .narrow,
            zeroValueUnits: .show(length: totalMinutes >= 60 ? 2 : 1)
        )
        let time = duration.formatted(style)
        return String(localized: "continueWatching.remaining", defaultValue: "Jäänud \(time)")
    }
    var positionLabel: String {
        let seconds = Int(position)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    var programme: Programme {
        let photo = imageAddress.map { ProgrammePhoto(photoTypes: ["17": .init(url: $0)]) }
        // Older entries stored the air date and episode title together.
        let legacyParts = subtitle.components(separatedBy: " · ")
        let legacyDate = programmeType == nil
            ? try? Date(legacyParts[0], strategy: Programme.legacyAirDateFormat.parseStrategy)
            : nil
        let legacyEpisodeTitle = legacyDate == nil ? subtitle : legacyParts.dropFirst().joined(separator: " · ")
        let type = programmeType ?? (seriesHeading != nil || !legacyEpisodeTitle.isEmpty ? "episode" : nil)
        let subHeading = programmeType == nil ? legacyEpisodeTitle : episodeSubHeading
        return Programme(id: id, heading: heading, subHeading: subHeading, lead: nil, type: type, scheduleStart: type == "episode" ? scheduleStart ?? legacyDate?.timeIntervalSince1970 : nil,
            photos: photo.map { [$0] }, horizontalPhotos: nil, verticalPhotos: nil, medias: nil,
            rootContent: seriesHeading.map { .init(heading: $0) }, savedReplayDeadline: replayDeadline, catalogueSource: catalogueSource)
    }
}

@MainActor
@Observable
final class WatchHistory {
    private(set) var records: [WatchEntry]
    private let defaults: UserDefaults
    // Keep the original key so existing installations retain their watch history.
    private let storageKey = "jupiter-watch-history-v1"
    private var availabilityDate = Date.now
    var inProgress: [WatchEntry] {
        let now = max(.now, availabilityDate)
        return records.filter { $0.isInProgress && $0.replayUnavailable != true && ($0.replayDeadline ?? .distantFuture) > now }
            .sorted { $0.updated > $1.updated }
    }

    var nextReplayDeadline: Date? { inProgress.compactMap(\.replayDeadline).min() }

    func updateAvailability() { availabilityDate = .now }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey), let saved = try? JSONDecoder().decode([WatchEntry].self, from: data) {
            var seen = Set<Int>()
            records = Array(saved.filter { $0.position.isFinite && $0.duration.isFinite && $0.duration > 0 && $0.position >= 0 && seen.insert($0.id).inserted }.prefix(100))
        } else { records = [] }
    }
    func isCompleted(_ id: Int) -> Bool { records.contains { $0.id == id && $0.completed } }
    func entry(for id: Int) -> WatchEntry? { records.first { $0.id == id && $0.isInProgress } }
    func save(_ programme: Programme, position: Double, duration: Double, ended: Bool = false) {
        guard position.isFinite, duration.isFinite, duration > 0, position >= 0 else { return }
        let position = min(position, duration)
        guard position >= 10 || ended else { return }
        let saved = records.first { $0.id == programme.id }
        let imageAddress = programme.imageURL?.absoluteString
        let entry = WatchEntry(id: programme.id, heading: String(programme.heading.prefix(240)),
            seriesHeading: programme.rootContent?.heading.map { String($0.prefix(240)) }, subtitle: String(programme.episodeLabel.prefix(240)),
            imageAddress: imageAddress ?? saved?.imageAddress, position: position, duration: duration, updated: Date(),
            catalogueSource: programme.source, completed: ended || position / duration >= 0.95,
            programmeType: programme.type ?? "", episodeSubHeading: programme.subHeading.map { String($0.prefix(240)) },
            scheduleStart: programme.scheduleStart,
            replayDeadline: programme.replayDeadline() ?? saved?.replayDeadline)
        records.removeAll { $0.id == programme.id }
        records.insert(entry, at: 0)
        records = Array(records.prefix(100))
        persist()
    }
    func refreshProgramme(for id: Int) async -> Programme? {
        guard let saved = entry(for: id) else { return nil }
        do {
            let source = saved.catalogueSource ?? .jupiter
            let detail = try await OnDemandAPI.detail(id, source: source)
            try Task.checkCancellation()
            guard detail.mainContent.id == id else { return nil }
            updateProgramme(detail.mainContent)
            return detail.mainContent
        } catch {
            return nil
        }
    }

    func updateProgramme(_ programme: Programme) {
        guard let index = records.firstIndex(where: {
            $0.id == programme.id && ($0.catalogueSource ?? .jupiter) == programme.source
        }) else { return }
        let imageAddress = programme.imageURL?.absoluteString
        let deadline = programme.replayDeadline()
        let unavailable = programme.playbackMedia == nil
        guard (imageAddress != nil && records[index].imageAddress != imageAddress)
                || records[index].replayUnavailable != unavailable
                || records[index].replayDeadline != deadline else { return }
        if let imageAddress { records[index].imageAddress = imageAddress }
        records[index].replayUnavailable = unavailable
        records[index].replayDeadline = deadline
        persist()
    }

    func remove(_ id: Int) {
        records.removeAll { $0.id == id }
        persist()
    }
    private func persist() {
        guard let data = try? JSONEncoder().encode(records), data.count < 350_000 else { return }
        defaults.set(data, forKey: storageKey)
    }
}
