import Foundation

struct LiveChannel: Identifiable {
    let id: String
    let title: String
    static let all = [
        LiveChannel(id: "etv", title: "ETV"),
        LiveChannel(id: "etv2", title: "ETV2"),
        LiveChannel(id: "etvpluss", title: "ETV+")
    ]
}

struct LiveSchedule: Decodable {
    let startTime: Double
    let endTime: Double
    let drm: Int?
    let name: String?
    let heading: String?

    var title: String {
        [name, heading].compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "Käimasolev saade"
    }

    func contains(_ date: Date) -> Bool {
        startTime <= date.timeIntervalSince1970 && date.timeIntervalSince1970 < endTime
    }

    var timeRange: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "et_EE")
        formatter.timeZone = TimeZone(identifier: "Europe/Tallinn")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: startTime)) + " – " + formatter.string(from: Date(timeIntervalSince1970: endTime))
    }
}

private struct LiveResponse: Decodable {
    let src: String
    let config: Configuration
    struct Configuration: Decodable {
        let isGeoBlocked: Bool?
        let drm: DRM?
    }
    struct DRM: Decodable {
        let srcs: Sources?
        let licenseServerUrls: LicenseURLs?
        let jwt: String?
        struct Sources: Decodable { let hls: String? }
        struct LicenseURLs: Decodable { let fairPlay: String? }
    }
}

enum LiveAPI {
    private struct Region: Decodable { let inEstonia: Bool }
    private static func media(_ channel: LiveChannel) async throws -> LiveResponse {
        var components = URLComponents(string: "https://services.err.ee/api/live/getLiveMediaData")!
        components.queryItems = [URLQueryItem(name: "channelName", value: channel.id)]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PlaybackFailure.invalidResponse }
        guard http.statusCode == 200 else { throw PlaybackFailure.http(http.statusCode) }
        return try JSONDecoder().decode(LiveResponse.self, from: data)
    }
    static func schedules(_ channel: LiveChannel) async throws -> [LiveSchedule] {
        var components = URLComponents(string: "https://services.err.ee/api/tvSchedule/getExactSchedules")!
        components.queryItems = [URLQueryItem(name: "type", value: "player"), URLQueryItem(name: "channel", value: channel.id)]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PlaybackFailure.invalidResponse }
        return try JSONDecoder().decode([LiveSchedule].self, from: data)
    }
    static func requiresFairPlay(_ channel: LiveChannel, at date: Date = Date()) async throws -> Bool? {
        let schedule = try await schedules(channel)
        return schedule.first { $0.contains(date) }.map { ($0.drm ?? 0) > 0 }
    }
    static func streamSource(for channel: LiveChannel, preferFairPlay: Bool? = nil) async throws -> PlaybackSource {
        var protected = preferFairPlay
        if protected == nil { protected = try? await requiresFairPlay(channel) }
        let media = try await media(channel)
        // The current version has no ERR account flow for EU residency portability.
        let (data, response) = try await URLSession.shared.data(from: URL(string: "https://services.err.ee/api/geoblock/getRegionalData")!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PlaybackFailure.invalidResponse }
        let region = try JSONDecoder().decode(Region.self, from: data)
        if media.config.isGeoBlocked == true && !region.inEstonia { throw PlaybackFailure.restricted }
        if protected == true {
            guard let drm = media.config.drm, let address = drm.srcs?.hls, !address.isEmpty else { throw FairPlayFailure.configuration }
            guard region.inEstonia else { throw PlaybackFailure.restricted }
            let configuration = try FairPlayConfiguration(licenseAddress: drm.licenseServerUrls?.fairPlay, token: drm.jwt) {
                let fresh = try await self.media(channel)
                guard let token = fresh.config.drm?.jwt, !token.isEmpty else { throw FairPlayFailure.configuration }
                return token
            }
            guard var url = URLComponents(string: address.hasPrefix("//") ? "https:" + address : address), url.scheme == "https" else { throw PlaybackFailure.invalidResponse }
            // Jupiter's web player adds a new numeric playback session to protected live paths.
            url.path = "/" + String(UInt64.random(in: 10_000_000_000_000...99_999_999_999_999)) + url.path
            guard let stream = url.url else { throw PlaybackFailure.invalidResponse }
            return PlaybackSource(url: stream, fairPlay: configuration)
        }
        let address = media.src.hasPrefix("//") ? "https:" + media.src : media.src
        guard let url = URL(string: address), url.scheme == "https" else { throw PlaybackFailure.invalidResponse }
        return PlaybackSource(url: url)
    }
}

enum PlaybackFailure: LocalizedError {
    case invalidResponse, restricted, http(Int)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Jupiteri esitusandmeid ei saanud lugeda."
        case .restricted: return "Selle kanali vaatamisel on ligipääsupiirang."
        case .http(let code): return "Jupiteri teenus vastas veaga HTTP \(code)."
        }
    }
}
