import Foundation

enum CatalogueSource: String, Codable {
    case jupiter, lasteekraan

    var domain: String { self == .lasteekraan ? "lasteekraan.err.ee" : "jupiter.err.ee" }
    var route: String { self == .lasteekraan ? "vaata-ja-kuula" : "video" }
    var rootID: Int { self == .lasteekraan ? 3592 : 3905 }
    var title: String { self == .lasteekraan ? String(localized: "catalogue.kidsTitle") : String(localized: "catalogue.title") }
}

struct Programme: Decodable, Identifiable {
    let id: Int
    let heading: String
    let subHeading: String?
    let lead: String?
    let type: String?
    let scheduleStart: Double?
    let photos: [ProgrammePhoto]?
    let horizontalPhotos: [ProgrammePhoto]?
    let verticalPhotos: [ProgrammePhoto]?
    let medias: [ProgrammeMedia]?
    let rootContent: RootProgramme?

    var catalogueSource: CatalogueSource? = nil
    var source: CatalogueSource { catalogueSource ?? .jupiter }
    var hasVideo: Bool { medias?.contains { $0.type == "video" && $0.src?.hls != nil } == true }

    func from(_ source: CatalogueSource) -> Programme {
        var copy = self
        copy.catalogueSource = source
        return copy
    }

    struct RootProgramme: Decodable {
        var id: Int? = nil
        let heading: String?
        var photos: [ProgrammePhoto]? = nil
        var horizontalPhotos: [ProgrammePhoto]? = nil
        var verticalPhotos: [ProgrammePhoto]? = nil
    }
    var imageURL: URL? {
        ProgrammePhoto.preferredURL(horizontal: horizontalPhotos ?? [], general: photos ?? [], vertical: verticalPhotos ?? [])
    }
    var posterURL: URL? {
        ProgrammePhoto.portraitURL(in: verticalPhotos ?? []) ?? imageURL
    }
    var descriptionText: String { Self.plainDescription(lead) }

    var playbackDetailProgramme: Programme {
        guard type == "episode", let root = rootContent, let id = root.id, id > 0, id != self.id else {
            return self
        }
        return Programme(id: id, heading: root.heading ?? heading, subHeading: nil, lead: nil,
                         type: "series", scheduleStart: nil, photos: root.photos,
                         horizontalPhotos: root.horizontalPhotos, verticalPhotos: root.verticalPhotos,
                         medias: nil, rootContent: nil, catalogueSource: source)
    }

    static func plainDescription(_ lead: String?) -> String {
        (lead ?? "").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
    static let legacyAirDateFormat = Date.FormatStyle.dateTime.day().month().year().locale(Locale(identifier: "et_EE"))

    private var airDateLabel: String? {
        guard let time = scheduleStart, time > 0 else { return nil }
        return Date(timeIntervalSince1970: time).formatted(Self.legacyAirDateFormat.locale(.current))
    }

    func cardTitle(showsSeriesTitle: Bool) -> String {
        guard type == "episode" else { return heading }
        if showsSeriesTitle { return rootContent?.heading ?? heading }
        if let cardSubtitle { return cardSubtitle }
        return airDateLabel.map { date in
            String(localized: "catalogue.episode.datedFallback", defaultValue: "Episood · \(date)")
        } ?? String(localized: "catalogue.episode.fallback")
    }

    var cardSubtitle: String? {
        guard let title = subHeading?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty, title != heading, title != rootContent?.heading else { return nil }
        return title
    }

    var playbackTitle: String { cardTitle(showsSeriesTitle: true) }

    var playbackSubtitle: String? {
        guard type == "episode" else { return nil }
        return cardSubtitle ?? (heading == playbackTitle ? cardTitle(showsSeriesTitle: false) : heading)
    }

    var episodeLabel: String {
        var parts: [String] = []
        if let airDateLabel { parts.append(airDateLabel) }
        if let subHeading, !subHeading.isEmpty, subHeading != heading { parts.append(subHeading) }
        return parts.joined(separator: " · ")
    }
}

struct ProgrammePhoto: Decodable {
    let photoTypes: [String: Variant]?
    struct Variant: Decodable { let url: String }

    static func preferredURL(horizontal: [Self], general: [Self], vertical: [Self]) -> URL? {
        if let url = landscapeURL(in: horizontal) { return url }

        // ERR can list a portrait source under both photos and verticalPhotos.
        let verticalVariants = Set(vertical.flatMap(\.variantAddresses))
        let otherPhotos = general.filter { verticalVariants.isDisjoint(with: $0.variantAddresses) }
        return landscapeURL(in: otherPhotos) ?? portraitURL(in: vertical + general + horizontal)
            ?? landscapeURL(in: general + vertical)
    }

    private var variantAddresses: [String] {
        photoTypes?.values.map { $0.url.hasPrefix("//") ? "https:" + $0.url : $0.url } ?? []
    }

    private static func landscapeURL(in photos: [Self]) -> URL? {
        // Detail responses omit the catalogue's 17/34 crops.
        url(in: photos, keys: ["17", "61", "34", "26", "48", "2", "6", "8"])
    }

    static func portraitURL(in photos: [Self]) -> URL? {
        url(in: photos, keys: ["80", "60"])
    }

    private static func url(in photos: [Self], keys: [String]) -> URL? {
        for photo in photos {
            for key in keys {
                guard let address = photo.photoTypes?[key]?.url,
                      let url = URL(string: address.hasPrefix("//") ? "https:" + address : address),
                      ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                      url.host != nil else { continue }
                return url
            }
        }
        return nil
    }
}

struct ProgrammeMedia: Decodable {
    let type: String?
    let src: Sources?
    let restrictions: Restrictions?
    let jwt: String?
    let licenseServerUrl: LicenseURLs?
    struct LicenseURLs: Decodable { let fairPlay: String? }
    struct Sources: Decodable { let hls: String? }
    struct Restrictions: Decodable { let drm: Bool?; let geoBlock: Bool? }
}

struct ProgrammeDetail: Decodable {
    var mainContent: Programme
    var seasonList: SeasonList?

    private enum CodingKeys: String, CodingKey { case mainContent, seasonList }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mainContent = try values.decode(Programme.self, forKey: .mainContent)
        if try !values.contains(.seasonList) || values.decodeNil(forKey: .seasonList) {
            seasonList = nil
        } else if let empty = try? values.nestedUnkeyedContainer(forKey: .seasonList), empty.isAtEnd {
            seasonList = nil
        } else {
            seasonList = try values.decode(SeasonList.self, forKey: .seasonList)
        }
    }

    func from(_ source: CatalogueSource) -> ProgrammeDetail {
        var copy = self
        copy.mainContent = mainContent.from(source)
        copy.seasonList = seasonList.map { SeasonList(items: $0.items?.map { $0.from(source) }) }
        return copy
    }
    struct SeasonList: Decodable { let items: [SeasonNode]? }
    struct SeasonNode: Decodable {
        let name: String?
        let firstContentId: Int?
        let contents: [Programme]?
        let items: [SeasonNode]?
        func from(_ source: CatalogueSource) -> SeasonNode {
            SeasonNode(name: name, firstContentId: firstContentId,
                contents: contents?.map { $0.from(source) }, items: items?.map { $0.from(source) })
        }
    }
    struct SeasonChoice: Identifiable {
        let id: Int
        let title: String
        let episodes: [Programme]
    }
    var seasons: [SeasonChoice] {
        func flatten(_ nodes: [SeasonNode], prefix: String = "") -> [SeasonChoice] {
            nodes.flatMap { node -> [SeasonChoice] in
                let title = [prefix, node.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
                if let children = node.items, !children.isEmpty { return flatten(children, prefix: title) }
                guard let id = node.firstContentId ?? node.contents?.first?.id else { return [] }
                return [SeasonChoice(id: id, title: title.isEmpty ? String(localized: "catalogue.season.fallback") : title, episodes: node.contents ?? [])]
            }
        }
        var seen = Set<Int>()
        return flatten(seasonList?.items ?? []).filter { seen.insert($0.id).inserted }
    }
    var currentSeasonID: Int? {
        let seasons = seasons
        return seasons.first { $0.id == mainContent.id }?.id
            ?? seasons.first { $0.episodes.contains { $0.id == mainContent.id } }?.id
    }

    var episodes: [Programme] { episodes(for: nil) }

    func episodes(for seasonID: Int?) -> [Programme] {
        let seasons = seasons
        let items = seasons.first { $0.id == seasonID }?.episodes
            ?? seasons.flatMap(\.episodes)
        var seen = Set<Int>()
        return items.filter { seen.insert($0.id).inserted }
    }
}

struct ProgrammeShelf: Identifiable {
    let id: Int
    let title: String
    let programmes: [Programme]
    let usesPortraitCards: Bool
}
