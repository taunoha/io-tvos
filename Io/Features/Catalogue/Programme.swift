import Foundation

enum CatalogueSource: String, Codable {
    case jupiter, lasteekraan

    var domain: String { self == .lasteekraan ? "lasteekraan.err.ee" : "jupiter.err.ee" }
    var route: String { self == .lasteekraan ? "vaata-ja-kuula" : "video" }
    var rootID: Int { self == .lasteekraan ? 3592 : 3905 }
    var title: String { self == .lasteekraan ? "Lasteekraan" : "Saated ja filmid" }
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
    }
    var imageURL: URL? {
        let candidates = (horizontalPhotos ?? []) + (photos ?? []) + (verticalPhotos ?? [])
        for photo in candidates {
            // Detail responses omit the catalogue's 17/34 crops.
            // Prefer a landscape crop before falling back to other sizes.
            for key in ["17", "61", "34", "26", "48", "2", "6", "8"] {
                guard let address = photo.photoTypes?[key]?.url,
                      let url = URL(string: address.hasPrefix("//") ? "https:" + address : address),
                      ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                      url.host != nil else { continue }
                return url
            }
        }
        return nil
    }
    var posterURL: URL? {
        for photo in verticalPhotos ?? [] {
            for key in ["80", "60"] {
                guard let address = photo.photoTypes?[key]?.url,
                      let url = URL(string: address.hasPrefix("//") ? "https:" + address : address),
                      ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                      url.host != nil else { continue }
                return url
            }
        }
        return imageURL
    }
    var descriptionText: String { Self.plainDescription(lead) }

    static func plainDescription(_ lead: String?) -> String {
        (lead ?? "").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
    static let airDateFormat = Date.FormatStyle.dateTime.day().month().year().locale(Locale(identifier: "et_EE"))

    private var airDateLabel: String? {
        guard let time = scheduleStart, time > 0 else { return nil }
        return Date(timeIntervalSince1970: time).formatted(Self.airDateFormat)
    }

    func cardTitle(showsSeriesTitle: Bool) -> String {
        guard type == "episode" else { return heading }
        if showsSeriesTitle { return rootContent?.heading ?? heading }
        if let cardSubtitle { return cardSubtitle }
        return airDateLabel.map { "Episood · " + $0 } ?? "Episood"
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
                return [SeasonChoice(id: id, title: title.isEmpty ? "Episoodid" : title, episodes: node.contents ?? [])]
            }
        }
        var seen = Set<Int>()
        return flatten(seasonList?.items ?? []).filter { seen.insert($0.id).inserted }
    }
    var episodes: [Programme] {
        var seen = Set<Int>()
        return seasons.flatMap(\.episodes).filter { seen.insert($0.id).inserted }
    }
}

struct ProgrammeShelf: Identifiable {
    let id: Int
    let title: String
    let programmes: [Programme]
    let usesPortraitCards: Bool
}
