import SwiftUI

struct TelekavaView: View {
    private struct Row: Hashable {
        let channelID: String
        let entryID: Int
    }

    private enum Focus: Hashable {
        case day(Date), row(Row), retry(String), favorite(Int)
    }

    private struct MissedFavorite: Identifiable {
        let programme: Programme
        let entry: TelekavaEntry
        let channel: LiveChannel

        var id: Int { programme.id }
    }

    private enum ChannelSchedule {
        case loaded([TelekavaEntry]), failed
    }

    private enum Playback: Identifiable {
        case live(LiveChannel), replay(Programme)

        var id: String {
            switch self {
            case .live(let channel): "live-\(channel.id)"
            case .replay(let programme): "replay-\(programme.id)"
            }
        }
    }

    @Environment(WatchHistory.self) private var history
    @Environment(ProgrammeFavorites.self) private var favorites
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(LiveChannel.lastWatchedKey) private var lastChannelID = "etv"
    @FocusState private var focus: Focus?
    @State private var day = TelekavaAPI.day(containing: .now)
    @State private var today = TelekavaAPI.day(containing: .now)
    @State private var loadedDay: Date?
    @State private var schedules: [String: ChannelSchedule] = [:]
    @State private var selected: Row?
    @State private var retry = 0
    @State private var replay: Programme?
    @State private var playback: Playback?
    @State private var returnFocus: Focus?

    private let colors: [Color] = [
        Color(red: 0.43, green: 0.75, blue: 1),
        Color(red: 0.55, green: 0.89, blue: 0.72),
        Color(red: 0.79, green: 0.66, blue: 1)
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            let now = context.date
            let replayID = selectedEntry?.replayID(at: now)
            let missed = missedFavorites(at: now)
            VStack(alignment: .leading, spacing: 26) {
                header
                HStack(alignment: .top, spacing: 24) {
                    ForEach(Array(LiveChannel.all.enumerated()), id: \.element.id) { index, channel in
                        column(channel, accent: colors[index], now: now)
                    }
                }
                if !missed.isEmpty {
                    missedFavoritesPanel(missed)
                }
            }
            .padding(.horizontal, IoDesign.contentInset)
            .padding(.vertical, IoDesign.focusRoom)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: TelekavaAPI.day(containing: now)) { _, newToday in
                if day == today || day < TelekavaAPI.day(-1, from: newToday) { day = newToday }
                today = newToday
            }
            .task(id: replayID) {
                replay = nil
                guard let replayID else { return }
                do {
                    try await Task.sleep(for: .milliseconds(350))
                    let page = try await OnDemandAPI.detail(replayID)
                    try Task.checkCancellation()
                    if page.mainContent.id == replayID, page.mainContent.hasVideo {
                        replay = page.mainContent
                    }
                } catch {
                    // A replay is offered only after the catalogue confirms a video.
                }
            }
        }
        .background {
            RadialGradient(colors: [Color(red: 0.12, green: 0.20, blue: 0.34), Color(white: 0.06)],
                           center: .topLeading, startRadius: 30, endRadius: 1100)
                .ignoresSafeArea()
        }
        .defaultFocus($focus, selected.map(Focus.row) ?? .day(day))
        .onChange(of: focus) { _, value in
            if case .row(let row) = value { selected = row }
        }
        .task(id: LoadRequest(day: day, retry: retry)) {
            await load(day)
        }
        .fullScreenCover(item: $playback, onDismiss: {
            if case .favorite(let id) = returnFocus, history.isCompleted(id) {
                focus = selected.map(Focus.row)
            } else {
                focus = returnFocus
            }
        }) { playback in
            switch playback {
            case .live(let channel):
                LivePlayerScreen(channel: channel)
            case .replay(let programme):
                OnDemandPlayerScreen(programme: programme, startPosition: history.entry(for: programme.id)?.position ?? 0, history: history)
            }
        }
    }

    private struct LoadRequest: Equatable {
        let day: Date
        let retry: Int
    }

    private var header: some View {
        let dateTitle = day.formatted(dateFormat.weekday(.wide).day().month(.wide))
        return HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Telekava").font(IoDesign.pageTitle).accessibilityAddTraits(.isHeader)
                Text(dateTitle.prefix(1).uppercased() + dateTitle.dropFirst())
                    .font(IoDesign.metadata)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 12) {
                ForEach(-1...3, id: \.self) { offset in
                    let date = TelekavaAPI.day(offset, from: today)
                    let focused = focus == .day(date)
                    Button {
                        day = date
                    } label: {
                        Text(dayLabel(offset, date: date))
                            .font(IoDesign.scheduleDayLabel)
                            .padding(.horizontal, 21).padding(.vertical, 10)
                            .foregroundStyle(focused ? .black : .white)
                            .background(focused ? .white : .white.opacity(day == date ? 0.18 : 0.08), in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(.white.opacity(0.55), lineWidth: day == date && !focused ? 1 : 0)
                            }
                            .scaleEffect(focused && !reduceMotion ? 1.06 : 1)
                    }
                    .ioCustomButtonFocus()
                    .focused($focus, equals: .day(date))
                    .accessibilityAddTraits(day == date ? .isSelected : [])
                }
            }
        }
    }

    private var dateFormat: Date.FormatStyle {
        Date.FormatStyle(locale: Locale(identifier: "et_EE"), timeZone: TelekavaAPI.timeZone)
    }

    private func dayLabel(_ offset: Int, date: Date) -> String {
        switch offset {
        case -1: "Eile"
        case 0: "Täna"
        case 1: "Homme"
        default: date.formatted(dateFormat.weekday(.abbreviated).day().month()).capitalized(with: dateFormat.locale)
        }
    }

    private func column(_ channel: LiveChannel, accent: Color, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle().fill(accent).frame(width: 12, height: 12).accessibilityHidden(true)
                Text(channel.title).font(IoDesign.scheduleChannelTitle).accessibilityAddTraits(.isHeader)
            }
            switch loadedDay == day ? schedules[channel.id] : nil {
            case .loaded(let entries) where !entries.isEmpty:
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(entries) { entry in
                                row(entry, channel: channel, accent: accent, now: now).id(entry.id)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .onAppear {
                        if let entry = anchor(in: entries, now: now) {
                            proxy.scrollTo(entry.id, anchor: .center)
                        }
                    }
                    .onChange(of: focus) { _, value in
                        if case .row(let row) = value, row.channelID == channel.id {
                            proxy.scrollTo(row.entryID, anchor: .center)
                        }
                    }
                }
            case .loaded:
                Text("Saatekava puudub").foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
            case .failed:
                VStack(alignment: .leading, spacing: 16) {
                    Text("Kava laadimine ebaõnnestus").foregroundStyle(.secondary)
                    Button("Proovi uuesti") { retry += 1 }
                        .focused($focus, equals: .retry(channel.id))
                }.frame(maxHeight: .infinity, alignment: .topLeading)
            case nil:
                ProgressView().accessibilityLabel("Laadin \(channel.title) kava")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ entry: TelekavaEntry, channel: LiveChannel, accent: Color, now: Date) -> some View {
        let row = Row(channelID: channel.id, entryID: entry.id)
        let focused = focus == .row(row)
        let current = entry.isCurrent(at: now)
        let showsReplayHint = focused && confirmedReplay(for: entry, at: now) != nil
        let replayHint = "Vaata järele"
        return Button {
            selected = row
            if let item = playback(for: entry, channel: channel, now: .now) {
                present(item, returningTo: .row(row))
            }
        } label: {
            HStack(spacing: 14) {
                Text(entry.startLabel)
                    .font(IoDesign.scheduleTimeLabel)
                    .foregroundStyle(focused ? .black.opacity(0.65) : .white.opacity(0.65))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 0) {
                        Text(entry.title).lineLimit(1)
                        if entry.isRepeat {
                            Text("*").fixedSize().accessibilityHidden(true)
                        }
                    }
                    .font(IoDesign.scheduleProgrammeTitle.weight(current ? .bold : .medium))
                    if showsReplayHint {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text(replayHint)
                        }
                        .font(IoDesign.scheduleReplayHint)
                        .foregroundStyle(.black.opacity(0.7))
                        .lineLimit(1)
                        .transition(.opacity)
                    }
                }
                Spacer(minLength: 0)
                if current {
                    Text("PRAEGU").font(.system(size: 14, weight: .bold)).tracking(0.8)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(focused ? .black.opacity(0.08) : accent.opacity(0.16), in: Capsule())
                        .foregroundStyle(focused ? .black : accent)
                }
            }
            .foregroundStyle(focused ? .black : .white)
            .padding(.horizontal, 18)
            .frame(height: showsReplayHint ? 94 : 66)
            .background(focused ? .white : .white.opacity(current ? 0.11 : 0.055),
                        in: RoundedRectangle(cornerRadius: 14))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: showsReplayHint)
        }
        .ioCustomButtonFocus()
        .focused($focus, equals: .row(row))
        .accessibilityLabel("\(channel.title), \(entry.startLabel), \(entry.title)\(entry.isRepeat ? ", kordus" : "")\(current ? ", praegu" : "")")
        .accessibilityHint(showsReplayHint ? replayHint : "")
        .accessibilityIdentifier("telekava-\(channel.id)-\(entry.id)")
        .onMoveCommand { direction in
            move(direction, from: row, entry: entry)
        }
    }

    private var selectedEntry: TelekavaEntry? {
        guard loadedDay == day, let selected else { return nil }
        return entries(for: selected.channelID).first { $0.id == selected.entryID }
    }

    private func missedFavorites(at now: Date) -> [MissedFavorite] {
        guard loadedDay == day, day == today || day == TelekavaAPI.day(-1, from: today),
              !favorites.entries.isEmpty else { return [] }
        let replays = LiveChannel.all.flatMap { channel in
            entries(for: channel.id).compactMap { entry -> MissedFavorite? in
                guard let programme = entry.favoriteReplay(at: now, favorites: favorites.entries),
                      !history.isCompleted(programme.id) else { return nil }
                return MissedFavorite(programme: programme, entry: entry, channel: channel)
            }
        }
        var seen = Set<Int>()
        return replays.sorted { $0.entry.startTime > $1.entry.startTime }
            .filter { seen.insert($0.id).inserted }
    }

    private func missedFavoritesPanel(_ missed: [MissedFavorite]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Maha magatud lemmikud", systemImage: "star.fill")
                .font(.system(size: 21, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(missed) { item in
                        Button {
                            present(.replay(item.programme), returningTo: .favorite(item.id))
                        } label: {
                            missedFavoriteLabel(item)
                        }
                        .ioCustomButtonFocus()
                        .focused($focus, equals: .favorite(item.id))
                        .accessibilityLabel("\(item.entry.title), \(item.channel.title), \(item.entry.startLabel), Vaata järele")
                        .accessibilityIdentifier("telekava-favorite-\(item.id)")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 20)
        .frame(height: 146)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 20))
        .focusSection()
    }

    private func missedFavoriteLabel(_ item: MissedFavorite) -> some View {
        let focused = focus == .favorite(item.id)
        return VStack(alignment: .leading, spacing: 4) {
            Text(item.entry.title)
                .font(.system(size: 22, weight: .semibold))
                .lineLimit(1)
            Label("\(item.channel.title) · \(item.entry.startLabel) · Vaata järele", systemImage: "play.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(focused ? .black.opacity(0.7) : .white.opacity(0.7))
        }
        .foregroundStyle(focused ? .black : .white)
        .frame(width: 338, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(focused ? .white : .white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }

    private func entries(for channelID: String) -> [TelekavaEntry] {
        guard case .loaded(let entries) = schedules[channelID] else { return [] }
        return entries
    }

    private func anchor(in entries: [TelekavaEntry], now: Date) -> TelekavaEntry? {
        if day == today {
            return entries.first { $0.isCurrent(at: now) }
                ?? entries.first { $0.startTime >= now.timeIntervalSince1970 }
                ?? entries.last
        }
        return entries.first
    }

    private func move(_ direction: MoveCommandDirection, from row: Row, entry: TelekavaEntry) {
        switch direction {
        case .left, .right:
            guard let index = LiveChannel.all.firstIndex(where: { $0.id == row.channelID }) else { return }
            let target = index + (direction == .left ? -1 : 1)
            guard LiveChannel.all.indices.contains(target) else { return }
            let channel = LiveChannel.all[target]
            let programmes = entries(for: channel.id)
            let reference = entry.isCurrent(at: .now) ? Date.now.timeIntervalSince1970 : entry.startTime
            if let nearest = programmes.first(where: { $0.startTime <= reference && reference < $0.endTime })
                ?? programmes.min(by: { abs($0.startTime - reference) < abs($1.startTime - reference) }) {
                focus = .row(Row(channelID: channel.id, entryID: nearest.id))
            } else if case .failed = schedules[channel.id] {
                focus = .retry(channel.id)
            }
        case .up, .down:
            let programmes = entries(for: row.channelID)
            guard let index = programmes.firstIndex(where: { $0.id == row.entryID }) else { return }
            let target = index + (direction == .up ? -1 : 1)
            if programmes.indices.contains(target) {
                focus = .row(Row(channelID: row.channelID, entryID: programmes[target].id))
            } else if direction == .up {
                focus = .day(day)
            } else if let favorite = missedFavorites(at: .now).first {
                focus = .favorite(favorite.id)
            }
        @unknown default:
            break
        }
    }

    private func playback(for entry: TelekavaEntry, channel: LiveChannel, now: Date) -> Playback? {
        if entry.isCurrent(at: now) { return .live(channel) }
        return confirmedReplay(for: entry, at: now).map(Playback.replay)
    }

    private func confirmedReplay(for entry: TelekavaEntry, at date: Date) -> Programme? {
        guard let replay, replay.id == entry.replayID(at: date) else { return nil }
        return replay
    }

    private func present(_ item: Playback, returningTo target: Focus?) {
        returnFocus = target
        playback = item
    }

    private func load(_ requestedDay: Date) async {
        let isToday = requestedDay == TelekavaAPI.day(containing: .now)
        let now = Date.now
        let results = await withTaskGroup(of: (String, ChannelSchedule).self) { group in
            for channel in LiveChannel.all {
                group.addTask {
                    do {
                        var entries = try await TelekavaAPI.schedule(channel: channel, day: requestedDay)
                        if isToday, let first = entries.first, first.startTime > now.timeIntervalSince1970,
                           let overnight = try? await TelekavaAPI.schedule(
                               channel: channel, day: TelekavaAPI.day(-1, from: requestedDay)
                           ) {
                            // ERR files programmes after midnight under the previous broadcast day.
                            let ids = Set(entries.map(\.id))
                            entries = overnight.filter {
                                $0.endTime > requestedDay.timeIntervalSince1970 &&
                                $0.startTime < first.startTime && !ids.contains($0.id)
                            } + entries
                        }
                        return (channel.id, .loaded(entries))
                    } catch {
                        return (channel.id, .failed)
                    }
                }
            }
            var results: [String: ChannelSchedule] = [:]
            for await (channel, schedule) in group { results[channel] = schedule }
            return results
        }
        guard !Task.isCancelled, requestedDay == day else { return }
        let isInitialLoad = loadedDay == nil && isToday
        schedules = results
        loadedDay = requestedDay
        let preferredChannel = selected?.channelID ?? lastChannelID
        let channels = [preferredChannel] + LiveChannel.all.map(\.id).filter { $0 != preferredChannel }
        selected = channels.lazy.compactMap { channelID in
            anchor(in: entries(for: channelID), now: now).map { Row(channelID: channelID, entryID: $0.id) }
        }.first
        if isInitialLoad, focus != nil, let selected {
            focus = .row(selected)
        }
    }
}
