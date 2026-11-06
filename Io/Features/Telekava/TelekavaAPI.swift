import Foundation

enum TelekavaAPI {
    static let timeZone = TimeZone(identifier: "Europe/Tallinn")!

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func day(containing date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func day(_ offset: Int, from day: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: day)!
    }

    static func schedule(channel: LiveChannel, day: Date) async throws -> [TelekavaEntry] {
        let date = calendar.dateComponents([.day, .month, .year], from: day)
        var url = URLComponents(string: "https://services.err.ee/api/tvSchedule/getTimelineSchedule")!
        url.queryItems = [
            URLQueryItem(name: "channel", value: channel.id),
            URLQueryItem(name: "day", value: date.day.map(String.init)),
            URLQueryItem(name: "month", value: date.month.map(String.init)),
            URLQueryItem(name: "year", value: date.year.map(String.init))
        ]
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let entries = try JSONDecoder().decode([TelekavaEntry].self, from: data)
        return entries.filter { $0.endTime > $0.startTime }.sorted { $0.startTime < $1.startTime }
    }
}

struct TelekavaEntry: Decodable, Identifiable {
    let id: Int
    let startTime: Double
    let endTime: Double
    let programName: String?
    let programNameTx: String?
    let name: String?
    let lead: String?
    let contentId: Int?
    let mediaExist: Bool?
    private let contents: [ReplayContent]?

    private struct ReplayContent: Decodable {
        let id: Int?
        let parentContentId: Int?
        let vodSiteDomain: String?
        let heading: String?
        let subHeading: String?
        let type: String?
        let medias: [ProgrammeMedia]?
    }

    var title: String {
        let heading = [programName, name].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Saade"
        return heading.hasSuffix("*") ? heading.dropLast().trimmingCharacters(in: .whitespacesAndNewlines) : heading
    }

    var isRepeat: Bool {
        [programNameTx, name, programName].contains {
            $0?.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("*") == true
        }
    }

    var startLabel: String { Self.timeLabel(startTime) }
    var timeRange: String { "\(startLabel)–\(Self.timeLabel(endTime))" }

    func isCurrent(at date: Date) -> Bool {
        startTime <= date.timeIntervalSince1970 && date.timeIntervalSince1970 < endTime
    }

    func replayID(at date: Date) -> Int? {
        guard endTime <= date.timeIntervalSince1970, mediaExist == true else { return nil }
        return contentId
    }

    func favoriteReplay(at date: Date, favorites: [ProgrammeFavorite]) -> Programme? {
        guard let id = replayID(at: date),
              let content = contents?.first(where: { $0.id == id }),
              content.medias?.contains(where: { $0.type == "video" && $0.src?.hls != nil }) == true,
              let favorite = favorites.first(where: {
                  $0.id == content.parentContentId && $0.source.domain == content.vodSiteDomain
              }) else { return nil }
        let series = favorite.programme
        return Programme(id: id, heading: content.heading ?? title, subHeading: content.subHeading,
                         lead: lead, type: content.type, scheduleStart: startTime,
                         photos: nil, horizontalPhotos: nil, verticalPhotos: nil, medias: nil,
                         rootContent: .init(id: series.id, heading: series.heading, photos: series.photos),
                         catalogueSource: favorite.source)
    }

    static func timeLabel(_ timestamp: Double) -> String {
        Date(timeIntervalSince1970: timestamp).formatted(
            Date.FormatStyle(locale: Locale(identifier: "et_EE"), timeZone: TelekavaAPI.timeZone)
                .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        )
    }
}
