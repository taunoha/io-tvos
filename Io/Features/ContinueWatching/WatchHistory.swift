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
    var artworkResolved: Bool? = nil

    var isInProgress: Bool { !completed && position >= 10 }
    var progress: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }
    var remainingLabel: String { "Jäänud \(max(1, Int(ceil((duration - position) / 60)))) min" }
    var positionLabel: String {
        let seconds = Int(position)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    var programme: Programme {
        let photo = imageAddress.map { ProgrammePhoto(photoTypes: ["17": .init(url: $0)]) }
        // Older entries stored the air date and episode title together.
        let legacyParts = subtitle.components(separatedBy: " · ")
        let legacyDate = programmeType == nil
            ? try? Date(legacyParts[0], strategy: Programme.airDateFormat.parseStrategy)
            : nil
        let legacyEpisodeTitle = legacyDate == nil ? subtitle : legacyParts.dropFirst().joined(separator: " · ")
        let type = programmeType ?? (seriesHeading != nil || !legacyEpisodeTitle.isEmpty ? "episode" : nil)
        let subHeading = programmeType == nil ? legacyEpisodeTitle : episodeSubHeading
        return Programme(id: id, heading: heading, subHeading: subHeading, lead: nil, type: type, scheduleStart: type == "episode" ? scheduleStart ?? legacyDate?.timeIntervalSince1970 : nil,
            photos: photo.map { [$0] }, horizontalPhotos: nil, verticalPhotos: nil, medias: nil,
            rootContent: seriesHeading.map { .init(heading: $0) }, catalogueSource: catalogueSource)
    }
}

@MainActor
@Observable
final class WatchHistory {
    private(set) var records: [WatchEntry]
    private let defaults: UserDefaults
    // Keep the original key so existing installations retain their watch history.
    private let storageKey = "jupiter-watch-history-v1"
    var inProgress: [WatchEntry] { records.filter(\.isInProgress).sorted { $0.updated > $1.updated } }

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
            scheduleStart: programme.scheduleStart, artworkResolved: imageAddress != nil ? true : saved?.artworkResolved)
        records.removeAll { $0.id == programme.id }
        records.insert(entry, at: 0)
        records = Array(records.prefix(100))
        persist()
    }
    func restoreImage(for id: Int) async {
        guard let saved = entry(for: id), saved.artworkResolved == nil else { return }
        do {
            let source = saved.catalogueSource ?? .jupiter
            let detail = try await OnDemandAPI.detail(id, source: source)
            try Task.checkCancellation()
            let imageURL = detail.mainContent.imageURL
            guard let index = records.firstIndex(where: {
                $0.id == id && ($0.catalogueSource ?? .jupiter) == source && $0.artworkResolved == nil
            }), imageURL != nil || records[index].imageAddress != nil else { return }
            if let imageURL {
                records[index].imageAddress = imageURL.absoluteString
            }
            records[index].artworkResolved = true
            persist()
        } catch {
            // Keep the saved position even when artwork is temporarily unavailable.
        }
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
