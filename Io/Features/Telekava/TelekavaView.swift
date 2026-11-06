import SwiftUI

struct TelekavaView: View {
    private struct Row: Hashable {
        let channelID: String
        let entryID: Int
    }

    private enum Focus: Hashable {
        case day(Date), row(Row), retry(String)
    }

    private struct MissedFavorite: Identifiable {
        let id: Int
        let entry: TelekavaEntry
        let channel: LiveChannel
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
    @State private var visibleRows: [String: Set<Int>] = [:]
    @State private var upwardBoundary: Row?
    @State private var pendingScheduleFocus: Date?
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
            VStack(alignment: .leading, spacing: IoDesign.shelfGap) {
                header
                VStack(alignment: .leading, spacing: IoDesign.Space.large) {
                    dayPicker
                    HStack(alignment: .top, spacing: IoDesign.Space.large) {
                        ForEach(Array(LiveChannel.all.enumerated()), id: \.element.id) { index, channel in
                            column(channel, accent: colors[index], now: now)
                        }
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
        .onChange(of: focus) { previous, value in
            if case .row(let row) = value {
                if case .day = previous, let selected, row != selected, loadedDay == day {
                    focus = .row(selected)
                    return
                }
                selected = row
            }
            if case .day(let focusedDay) = value {
                if case .row = previous, focusedDay != day { focus = .day(day) }
                return
            }
            pendingScheduleFocus = nil
        }
        .task(id: LoadRequest(day: day, retry: retry)) {
            await load(day)
        }
        .fullScreenCover(item: $playback, onDismiss: {
            focus = returnFocus
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
        return HStack(alignment: .firstTextBaseline, spacing: IoDesign.Space.large) {
            Text("Telekava").font(IoDesign.pageTitle).accessibilityAddTraits(.isHeader)
            Text(dateTitle.prefix(1).uppercased() + dateTitle.dropFirst())
                .font(IoDesign.metadata)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dayPicker: some View {
        HStack(spacing: IoDesign.Space.medium) {
            ForEach(-1...3, id: \.self) { offset in
                let date = TelekavaAPI.day(offset, from: today)
                let focused = focus == .day(date)
                Button {
                    pendingScheduleFocus = nil
                    if day != date { upwardBoundary = nil }
                    day = date
                } label: {
                    Text(dayLabel(offset, date: date))
                        .font(IoDesign.scheduleDayLabel)
                        .padding(.horizontal, IoDesign.Space.large).padding(.vertical, IoDesign.Space.small)
                        .frame(maxWidth: .infinity)
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
                .onMoveCommand { direction in
                    if direction == .down { focusSchedule() }
                }
            }
        }
        .focusSection()
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
        VStack(alignment: .leading, spacing: IoDesign.sectionHeadingGap) {
            HStack(spacing: IoDesign.Space.medium) {
                Circle().fill(accent).frame(width: 12, height: 12).accessibilityHidden(true)
                Text(channel.title).font(IoDesign.scheduleChannelTitle).accessibilityAddTraits(.isHeader)
            }
            switch loadedDay == day ? schedules[channel.id] : nil {
            case .loaded(let entries) where !entries.isEmpty:
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: IoDesign.Space.small) {
                            ForEach(entries) { entry in
                                row(entry, channel: channel, accent: accent, now: now)
                                    .onGeometryChange(for: Bool.self) { geometry in
                                        let space = NamedCoordinateSpace.scrollView(axis: .vertical)
                                        guard let bounds = geometry.bounds(of: space) else { return false }
                                        let rowFrame = geometry.frame(in: space)
                                        let viewport = CGRect(origin: .zero, size: bounds.size)
                                        return rowFrame.height > 0
                                            && rowFrame.intersection(viewport).height >= rowFrame.height - 3
                                    } action: { visible in
                                        if visible {
                                            visibleRows[channel.id, default: []].insert(entry.id)
                                        } else {
                                            visibleRows[channel.id]?.remove(entry.id)
                                        }
                                    }
                                    .id(entry.id)
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
                        if case .row(let row) = value, row.channelID == channel.id,
                           visibleRows[channel.id]?.contains(row.entryID) != true {
                            proxy.scrollTo(row.entryID)
                        }
                    }
                }
            case .loaded:
                Text("Saatekava puudub").foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
            case .failed:
                VStack(alignment: .leading, spacing: IoDesign.Space.medium) {
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
            HStack(spacing: IoDesign.Space.medium) {
                Text(entry.startLabel)
                    .font(IoDesign.scheduleTimeLabel)
                    .foregroundStyle(focused ? .black.opacity(0.65) : .white.opacity(0.65))
                HStack(spacing: 0) {
                    Text(entry.title).lineLimit(1)
                    if entry.isRepeat {
                        Text("*").fixedSize().accessibilityHidden(true)
                    }
                }
                .font(IoDesign.scheduleProgrammeTitle.weight(current ? .bold : .medium))
                Spacer(minLength: 0)
                if current {
                    Text("PRAEGU").font(IoDesign.badge).tracking(0.8)
                        .padding(.horizontal, IoDesign.Space.small).padding(.vertical, IoDesign.Space.xSmall)
                        .background(focused ? .black.opacity(0.08) : accent.opacity(0.16), in: Capsule())
                        .foregroundStyle(focused ? .black : accent)
                } else if showsReplayHint {
                    HStack(spacing: IoDesign.Space.xSmall) {
                        Image(systemName: "play.fill")
                            .font(IoDesign.inlineIcon)
                        Text(replayHint)
                    }
                    .font(IoDesign.scheduleReplayHint)
                    .foregroundStyle(.black.opacity(0.7))
                    .fixedSize()
                    .accessibilityHidden(true)
                }
            }
            .foregroundStyle(focused ? .black : .white)
            .padding(.horizontal, IoDesign.Space.large)
            .frame(height: 66)
            .background(focused ? .white : .white.opacity(current ? 0.11 : 0.055),
                        in: RoundedRectangle(cornerRadius: 14))
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
                return MissedFavorite(id: programme.id, entry: entry, channel: channel)
            }
        }
        var seen = Set<Int>()
        return replays.sorted { $0.entry.startTime > $1.entry.startTime }
            .filter { seen.insert($0.id).inserted }
    }

    private func missedFavoritesPanel(_ missed: [MissedFavorite]) -> some View {
        VStack(alignment: .leading, spacing: IoDesign.sectionHeadingGap) {
            Label("Maha magatud lemmikud", systemImage: "star.fill")
                .font(IoDesign.metadata.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                HStack(spacing: IoDesign.Space.medium) {
                    ForEach(missed) { item in
                        missedFavoriteLabel(item)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("telekava-favorite-\(item.id)")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, IoDesign.Space.large)
        .frame(height: 146)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 20))
    }

    private func missedFavoriteLabel(_ item: MissedFavorite) -> some View {
        VStack(alignment: .leading, spacing: IoDesign.Space.xSmall) {
            Text(item.entry.title)
                .font(IoDesign.metadata.weight(.semibold))
                .lineLimit(1)
            Text("\(item.channel.title) · \(item.entry.startLabel)")
                .font(IoDesign.metadata)
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .frame(width: 338, alignment: .leading)
        .padding(.horizontal, IoDesign.Space.medium)
        .padding(.vertical, IoDesign.Space.small)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
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

    private func focusSchedule() {
        guard loadedDay == day else {
            pendingScheduleFocus = day
            return
        }
        if let selected {
            focus = .row(selected)
        } else if let channel = LiveChannel.all.first(where: {
            if case .failed = schedules[$0.id] { return true }
            return false
        }) {
            focus = .retry(channel.id)
        }
    }

    private func move(_ direction: MoveCommandDirection, from row: Row, entry: TelekavaEntry) {
        if direction != .up { upwardBoundary = nil }
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
            if direction == .up {
                // tvOS may scroll an earlier row into view as it moves focus.
                // Keep the visible upper edge from the start of this upward movement.
                if upwardBoundary?.channelID != row.channelID,
                   let first = programmes.first(where: { visibleRows[row.channelID]?.contains($0.id) == true }) {
                    upwardBoundary = Row(channelID: row.channelID, entryID: first.id)
                }
                let boundary = programmes.firstIndex { $0.id == upwardBoundary?.entryID } ?? 0
                if index <= boundary {
                    selected = row
                    focus = .day(day)
                    return
                }
            }
            let target = index + (direction == .up ? -1 : 1)
            if programmes.indices.contains(target) {
                focus = .row(Row(channelID: row.channelID, entryID: programmes[target].id))
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
        if pendingScheduleFocus == requestedDay {
            pendingScheduleFocus = nil
            focusSchedule()
        } else if isInitialLoad, focus != nil, let selected {
            focus = .row(selected)
        }
    }
}
