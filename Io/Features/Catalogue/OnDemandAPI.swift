import Foundation

enum OnDemandError: LocalizedError {
    case service(Int), noMedia, protectedContent, regionRestricted
    var errorDescription: String? {
        switch self {
        case .service(let status): return String(localized: "catalogue.error.http", defaultValue: "Jupiteri andmeid ei saanud laadida (HTTP \(status)).")
        case .noMedia: return String(localized: "catalogue.error.noMedia")
        case .protectedContent: return String(localized: "catalogue.error.protected")
        case .regionRestricted: return String(localized: "catalogue.error.regionRestricted")
        }
    }
}

enum OnDemandAPI {
    private struct Envelope<T: Decodable>: Decodable { let data: T }
    struct Catalogue: Decodable {
        let category: Category
        struct Category: Decodable { let frontPage: [Row] }
        struct Row: Decodable {
            let header: String?
            let highTimeline: Bool?
            let data: [Programme]?
            let userBasedTimeline: Bool?
            let manual: Manual?
            struct Manual: Decodable { let banner: Bool?; let userBasedTimeline: Bool? }
        }
    }

    static func shelves(from catalogue: Catalogue, source: CatalogueSource) -> [ProgrammeShelf] {
        let videoRows: Set<String> = ["Lasteekraan soovitab", "Viimati lisatud multikad",
            "Viimati lisatud saated ja filmid", "Multikad", "Animafilmid", "Filmid", "Sarjad ja saated", "Mudilastele"]
        return catalogue.category.frontPage.enumerated().compactMap { index, row in
            if source == .lasteekraan {
                guard row.userBasedTimeline != true, row.manual?.userBasedTimeline != true,
                      row.manual?.banner != true, videoRows.contains(row.header ?? "") else { return nil }
            }
            var seen = Set<Int>()
            let items = (row.data ?? []).filter {
                (source != .lasteekraan || ["series", "episode", "movie", "clip"].contains($0.type ?? ""))
                    && seen.insert($0.id).inserted
            }.map { $0.from(source) }
            guard !items.isEmpty else { return nil }
            return ProgrammeShelf(id: index, title: (row.header?.isEmpty == false ? row.header! : String(localized: "catalogue.featuredFallback")),
                programmes: items, usesPortraitCards: row.highTimeline == true)
        }
    }
    struct SearchPage {
        let programmes: [Programme]
        let hasMore: Bool
    }
    private struct SearchResult: Decodable {
        let video: Results?
        struct Results: Decodable {
            let contents: [Programme]?
            let totalFound: Int?
            let page: Int?
            let perPage: Int?
        }
    }
    private struct Region: Decodable { let inEstonia: Bool }

    private static func get<T: Decodable>(_ path: String, _ query: [URLQueryItem] = []) async throws -> T {
        var url = URLComponents(string: "https://services.err.ee" + path)!
        url.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw OnDemandError.service(status) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func catalogue(source: CatalogueSource = .jupiter) async throws -> [ProgrammeShelf] {
        let response: Envelope<Catalogue> = try await get("/api/v2/category/getByUrl", [
            URLQueryItem(name: "url", value: source.route), URLQueryItem(name: "domain", value: source.domain), URLQueryItem(name: "page", value: "web")])
        return shelves(from: response.data, source: source)
    }

    static func detail(_ id: Int, source: CatalogueSource = .jupiter) async throws -> ProgrammeDetail {
        let response: Envelope<ProgrammeDetail> = try await get("/api/v2/vodContent/getContentPageData", [
            URLQueryItem(name: "contentId", value: String(id)), URLQueryItem(name: "rootId", value: String(source.rootID)), URLQueryItem(name: "page", value: "web")])
        return response.data.from(source)
    }

    static func search(_ phrase: String, page: Int) async throws -> SearchPage {
        let limit = 24
        let options: [String: Any] = ["phrase": phrase, "page": page, "limit": limit, "searchTypes": ["video"]]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: options), as: UTF8.self)
        let response: SearchResult = try await get("/api/search/getVodContents2/", [URLQueryItem(name: "type", value: "video"), URLQueryItem(name: "options", value: json)])
        guard let video = response.video, let programmes = video.contents, !programmes.isEmpty,
              video.page == nil || video.page == page else {
            return SearchPage(programmes: [], hasMore: false)
        }
        let pageSize = video.perPage.flatMap { $0 > 0 ? $0 : nil } ?? limit
        let hasMore = video.totalFound.map { $0 > 0 && ($0 - 1) / pageSize >= page } ?? (programmes.count >= pageSize)
        return SearchPage(programmes: programmes, hasMore: hasMore)
    }

    static func playbackSource(_ id: Int, source: CatalogueSource = .jupiter) async throws -> PlaybackSource {
        let page = try await detail(id, source: source)
        let sources = page.mainContent.medias ?? []
        guard !sources.isEmpty else { throw OnDemandError.noMedia }
        guard let media = sources.first(where: { $0.src?.hls != nil && (source != .lasteekraan || $0.type == "video") }) else { throw OnDemandError.noMedia }
        if media.restrictions?.geoBlock == true {
            let region: Region = try await get("/api/geoblock/getRegionalData")
            guard region.inEstonia else { throw OnDemandError.regionRestricted }
        }
        guard let address = media.src?.hls,
              let url = URL(string: address.hasPrefix("//") ? "https:" + address : address), url.scheme == "https" else { throw OnDemandError.noMedia }
        if media.restrictions?.drm == true {
            let configuration = try FairPlayConfiguration(licenseAddress: media.licenseServerUrl?.fairPlay, token: media.jwt) {
                let fresh = try await detail(id, source: source)
                guard let token = fresh.mainContent.medias?.first(where: { $0.restrictions?.drm == true })?.jwt, !token.isEmpty else { throw FairPlayFailure.configuration }
                return token
            }
            return PlaybackSource(url: url, fairPlay: configuration)
        }
        return PlaybackSource(url: url)
    }
}
