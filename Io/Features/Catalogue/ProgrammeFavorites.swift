import Foundation
import Observation

struct ProgrammeFavorite: Codable {
    let id: Int
    let source: CatalogueSource
    let heading: String
    private(set) var imageAddress: String?
    private(set) var artworkResolved: Bool?

    init?(programme: Programme, mainContent: Programme) {
        let series: Programme
        if programme.type == "series" {
            series = programme
        } else if mainContent.type == "series" {
            series = mainContent
        } else if let root = mainContent.rootContent ?? programme.rootContent,
                  let id = root.id, id > 0, let heading = root.heading, !heading.isEmpty {
            series = Programme(id: id, heading: heading, subHeading: nil, lead: nil,
                type: "series", scheduleStart: nil, photos: root.photos,
                horizontalPhotos: root.horizontalPhotos, verticalPhotos: root.verticalPhotos, medias: nil,
                rootContent: nil)
        } else {
            return nil
        }
        id = series.id
        source = programme.source
        heading = series.heading
        imageAddress = series.imageURL?.absoluteString ?? mainContent.imageURL?.absoluteString
        resolveArtwork(from: mainContent, series: series)
    }

    mutating func resolveArtwork(from content: Programme, series: Programme? = nil) {
        let root = content.rootContent.flatMap { $0.id == id ? $0 : nil }
        let series = series ?? (content.id == id ? content : nil)
        let horizontal = (root?.horizontalPhotos ?? []) + (series?.horizontalPhotos ?? [])
        let general = (root?.photos ?? []) + (series?.photos ?? [])
        let vertical = (root?.verticalPhotos ?? []) + (series?.verticalPhotos ?? [])
        if let url = ProgrammePhoto.preferredURL(horizontal: horizontal, general: general, vertical: vertical) {
            imageAddress = url.absoluteString
        }
        artworkResolved = true
    }

    var programme: Programme {
        let photo = imageAddress.map { ProgrammePhoto(photoTypes: ["17": .init(url: $0)]) }
        return Programme(id: id, heading: heading, subHeading: nil, lead: nil,
            type: "series", scheduleStart: nil, photos: photo.map { [$0] },
            horizontalPhotos: nil, verticalPhotos: nil, medias: nil, rootContent: nil,
            catalogueSource: source)
    }
}

@MainActor
@Observable
final class ProgrammeFavorites {
    private(set) var entries: [ProgrammeFavorite]
    private let defaults: UserDefaults
    private let storageKey = "io-programme-favorites-v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([ProgrammeFavorite].self, from: $0) } ?? []
    }

    func contains(_ favorite: ProgrammeFavorite) -> Bool {
        entries.contains { $0.id == favorite.id && $0.source == favorite.source }
    }

    func toggle(_ favorite: ProgrammeFavorite) {
        var updated = entries
        if let index = updated.firstIndex(where: { $0.id == favorite.id && $0.source == favorite.source }) {
            updated.remove(at: index)
        } else {
            updated.insert(favorite, at: 0)
        }
        save(updated)
    }

    func resolveLegacyArtwork() async {
        for favorite in entries where favorite.artworkResolved == nil {
            guard !Task.isCancelled else { return }
            guard let detail = try? await OnDemandAPI.detail(favorite.id, source: favorite.source),
                  !Task.isCancelled,
                  let index = entries.firstIndex(where: {
                      $0.id == favorite.id && $0.source == favorite.source && $0.artworkResolved == nil
                  }) else { continue }
            var updated = entries
            updated[index].resolveArtwork(from: detail.mainContent)
            save(updated)
        }
    }

    private func save(_ updated: [ProgrammeFavorite]) {
        guard let data = try? JSONEncoder().encode(updated) else { return }
        defaults.set(data, forKey: storageKey)
        entries = updated
    }
}
