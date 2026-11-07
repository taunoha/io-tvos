import SwiftUI

struct TelekavaView: View {
    private struct Row: Hashable {
        let channelID: String
        let entryID: Int
    }

    private enum Focus: Hashable {
        case day(Date), row(Row), retry(String), playbackAction
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(LiveChannel.lastWatchedKey) private var lastChannelID = "etv"
    @FocusState private var focus: Focus?
    @State private var day = TelekavaAPI.day(containing: .now)
    @State private var today = TelekavaAPI.day(containing: .now)
    @State private var loadedDay: Date?
    @State private var schedules: [String: ChannelSchedule] = [:]
    @State private var selected: Row?
    @State private var windowStart: TimeInterval = 0
    @State private var navigationTime: TimeInterval?
    @State private var pendingRowFocus: Row?

    private let windowDuration: TimeInterval = 3 * 60 * 60
    private let tickInterval: TimeInterval = 30 * 60

    private var windowEnd: TimeInterval { windowStart + windowDuration }
    @State private var pendingScheduleFocus: Date?
    @State private var retry = 0
    @State private var catalogueDetail: Programme?
    @State private var playback: Playback?
    @State private var returnFocus: Focus?

    var body: some View {
        TimelineView(.periodic(from: Date(timeIntervalSince1970: 0), by: 10)) { context in
            let now = context.date
            let contentID = selectedEntry?.contentId
            ScrollView {
                VStack(alignment: .leading, spacing: IoDesign.shelfGap) {
                    header(now: now)
                    dayPicker
                    guide(now: now)
                    if let entry = selectedEntry,
                       let channel = LiveChannel.all.first(where: { $0.id == selected?.channelID }) {
                        programmeDetail(entry, channel: channel, now: now)
                    }
                }
                .padding(.horizontal, IoDesign.contentInset)
                .padding(.vertical, IoDesign.focusRoom)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .onChange(of: TelekavaAPI.day(containing: now)) { _, newToday in
                if day == today || day < TelekavaAPI.day(-1, from: newToday) { day = newToday }
                today = newToday
            }
            .task(id: contentID) {
                catalogueDetail = nil
                guard let contentID else { return }
                do {
                    try await Task.sleep(for: .milliseconds(350))
                    let page = try await OnDemandAPI.detail(contentID)
                    try Task.checkCancellation()
                    if page.mainContent.id == contentID {
                        catalogueDetail = page.mainContent
                    }
                } catch {
                    // The schedule supplies the basic details when the catalogue is unavailable.
                }
            }
        }
        .background {
            LinearGradient(colors: [Color(red: 0.09, green: 0.11, blue: 0.16),
                                    Color(red: 0.035, green: 0.045, blue: 0.07)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        }
        .defaultFocus($focus, selected.map(Focus.row) ?? .day(day))
        .onChange(of: focus) { previous, value in
            if case .row(let row) = value {
                if let selected, row != selected, loadedDay == day {
                    switch previous {
                    case .day, .playbackAction:
                        focus = .row(selected)
                        return
                    default:
                        break
                    }
                }
                if row != selected, pendingRowFocus == nil,
                   let entry = entries(for: row.channelID).first(where: { $0.id == row.entryID }) {
                    if case .row(let previousRow) = previous, previousRow.channelID != row.channelID,
                       let reference = navigationTime,
                       let target = programme(on: row.channelID, at: reference) {
                        focusProgramme(target, channelID: row.channelID, reference: reference)
                        return
                    }
                    selected = row
                    navigationTime = entry.isCurrent(at: .now)
                        ? Date.now.timeIntervalSince1970 : max(entry.startTime, windowStart)
                }
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
            if returnFocus == .playbackAction,
               let entry = selectedEntry,
               confirmedReplay(for: entry, at: .now) == nil {
                focusSchedule()
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

    private func header(now: Date) -> some View {
        let dateTitle = day.formatted(dateFormat.weekday(.wide).day().month(.wide))
        let time = TelekavaEntry.timeLabel(now.timeIntervalSince1970)
        return HStack(alignment: .firstTextBaseline, spacing: IoDesign.Space.large) {
            VStack(alignment: .leading, spacing: IoDesign.sectionHeadingGap) {
                Text("Telekava").font(IoDesign.pageTitle).accessibilityAddTraits(.isHeader)
                Text(dateTitle.prefix(1).uppercased() + dateTitle.dropFirst())
                    .font(IoDesign.metadata)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(time)
                .font(IoDesign.sectionTitle.monospacedDigit())
                .accessibilityLabel("Kell \(time)")
        }
    }

    private var dayPicker: some View {
        HStack(spacing: IoDesign.Space.medium) {
            ForEach(-1...3, id: \.self) { offset in
                let date = TelekavaAPI.day(offset, from: today)
                let focused = focus == .day(date)
                Button {
                    pendingScheduleFocus = nil
                    pendingRowFocus = nil
                    day = date
                } label: {
                    Text(dayLabel(offset, date: date))
                        .font(IoDesign.body.weight(.semibold))
                        .padding(.horizontal, IoDesign.Space.large).padding(.vertical, IoDesign.Space.small)
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

    private func guide(now: Date) -> some View {
        HStack(alignment: .top, spacing: IoDesign.sectionHeadingGap) {
            VStack(alignment: .leading, spacing: IoDesign.sectionHeadingGap) {
                Color.clear.frame(height: IoDesign.scheduleAxisHeight).accessibilityHidden(true)
                ForEach(LiveChannel.all) { channel in
                    Text(channel.title)
                        .font(IoDesign.scheduleCellTitle)
                        .frame(maxWidth: .infinity)
                        .frame(height: IoDesign.scheduleRowHeight)
                        .background(.white.opacity(0.075),
                                    in: RoundedRectangle(cornerRadius: IoDesign.scheduleGridCornerRadius))
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .frame(width: IoDesign.scheduleChannelWidth, alignment: .leading)

            GeometryReader { geometry in
                let width = geometry.size.width
                VStack(spacing: IoDesign.sectionHeadingGap) {
                    timeAxis(width: width)
                    VStack(spacing: IoDesign.sectionHeadingGap) {
                        ForEach(LiveChannel.all) { channel in
                            channelTrack(channel, now: now, width: width)
                        }
                    }
                    .overlay {
                        guideEdgeShadows
                            .mask { guideCardMask(width: width) }
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .leading) {
                    let x = position(of: now.timeIntervalSince1970, width: width)
                    if loadedDay == day, day == today, x >= 0, x < width {
                        Rectangle()
                            .fill(.cyan)
                            .frame(width: IoDesign.Space.xxSmall)
                            .padding(.top, IoDesign.scheduleAxisHeight)
                            .offset(x: x)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .clipped()
            }
            .frame(height: IoDesign.scheduleAxisHeight
                   + CGFloat(LiveChannel.all.count) * (IoDesign.scheduleRowHeight + IoDesign.sectionHeadingGap))
        }
    }

    private var guideEdgeShadows: some View {
        let hiddenEntries = LiveChannel.all.flatMap { entries(for: $0.id) }.filter(needsMoreRoom)
        let hasEarlier = loadedDay == day && hiddenEntries.contains { $0.startTime < windowStart }
        let hasLater = loadedDay == day && hiddenEntries.contains { $0.endTime > windowEnd }
        return HStack(spacing: 0) {
            if hasEarlier {
                guideEdgeShadow(from: .leading, to: .trailing)
            }
            Spacer(minLength: 0)
            if hasLater {
                guideEdgeShadow(from: .trailing, to: .leading)
            }
        }
    }

    private func guideEdgeShadow(from start: UnitPoint, to end: UnitPoint) -> some View {
        LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: start, endPoint: end)
            .frame(width: IoDesign.scheduleEdgeShadowWidth)
    }

    private func guideCardMask(width: CGFloat) -> some View {
        VStack(spacing: IoDesign.sectionHeadingGap) {
            ForEach(LiveChannel.all) { channel in
                ZStack(alignment: .leading) {
                    ForEach(trackEntries(for: channel.id)) { entry in
                        let frame = programmeFrame(entry, trackWidth: width)
                        RoundedRectangle(cornerRadius: IoDesign.scheduleGridCornerRadius)
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX)
                    }
                }
                .frame(width: width, height: IoDesign.scheduleRowHeight, alignment: .leading)
            }
        }
    }

    private func trackEntries(for channelID: String) -> [TelekavaEntry] {
        guard loadedDay == day else { return [] }
        // Keep nearby cells mounted so they can slide in and out of the viewport.
        return entries(for: channelID).filter {
            $0.endTime > windowStart - windowDuration && $0.startTime < windowEnd + windowDuration
        }
    }

    private func programmeFrame(_ entry: TelekavaEntry, trackWidth: CGFloat) -> CGRect {
        let left = min(trackWidth, max(0, position(of: entry.startTime, width: trackWidth)))
        let right = min(trackWidth, max(0, position(of: entry.endTime, width: trackWidth)))
        let visibleWidth = right - left
        return CGRect(x: left, y: 0, width: visibleWidth - min(IoDesign.Space.xSmall, visibleWidth / 4),
                      height: IoDesign.scheduleRowHeight)
    }

    private func position(of timestamp: TimeInterval, width: CGFloat) -> CGFloat {
        width * (timestamp - windowStart) / windowDuration
    }

    private func timeAxis(width: CGFloat) -> some View {
        let first = Int(ceil(windowStart / tickInterval))
        return ZStack(alignment: .leading) {
            if loadedDay == day {
                ForEach(first..<(first + Int(windowDuration / tickInterval)), id: \.self) { index in
                    let tick = Double(index) * tickInterval
                    Text(TelekavaEntry.timeLabel(tick))
                        .font(IoDesign.scheduleTimeLabel)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .offset(x: position(of: tick, width: width))
                }
            }
        }
        .frame(width: width, height: IoDesign.scheduleAxisHeight, alignment: .leading)
        .accessibilityHidden(true)
    }

    private func channelTrack(_ channel: LiveChannel, now: Date, width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            switch loadedDay == day ? schedules[channel.id] : nil {
            case .loaded(let entries) where !entries.isEmpty:
                ForEach(trackEntries(for: channel.id)) { entry in
                    let frame = programmeFrame(entry, trackWidth: width)
                    programmeCell(entry, channel: channel, now: now, width: frame.width)
                        .offset(x: frame.minX)
                        .disabled(frame.width == 0)
                        .accessibilityHidden(frame.width == 0)
                }
            case .loaded:
                Text("Saatekava puudub").font(IoDesign.metadata).foregroundStyle(.secondary)
            case .failed:
                HStack(spacing: IoDesign.Space.large) {
                    Text("Kava laadimine ebaõnnestus").font(IoDesign.metadata).foregroundStyle(.secondary)
                    Button("Proovi uuesti") { retry += 1 }
                        .font(IoDesign.metadata)
                        .focused($focus, equals: .retry(channel.id))
                        .onMoveCommand { direction in
                            moveBetweenChannels(direction, from: channel.id)
                        }
                }
            case nil:
                ProgressView().accessibilityLabel("Laadin \(channel.title) kava")
            }
        }
        .frame(width: width, height: IoDesign.scheduleRowHeight, alignment: .leading)
    }

    private func programmeCell(_ entry: TelekavaEntry, channel: LiveChannel,
                               now: Date, width: CGFloat) -> some View {
        let row = Row(channelID: channel.id, entryID: entry.id)
        let focused = focus == .row(row)
        let isSelected = selected == row
        let current = entry.isCurrent(at: now)
        let shape = RoundedRectangle(cornerRadius: IoDesign.scheduleGridCornerRadius)
        return Button {
            if let item = playback(for: entry, channel: channel, now: .now) {
                present(item, returningTo: .row(row))
            }
        } label: {
            VStack(alignment: .leading, spacing: IoDesign.Space.xxSmall) {
                Text(entry.title + (entry.isRepeat ? "*" : ""))
                    .lineLimit(1)
                    .font(IoDesign.scheduleCellTitle)
                Text(entry.timeRange)
                    .lineLimit(1)
                    .font(IoDesign.scheduleTimeLabel)
                    .opacity(0.8)
                if current {
                    let elapsed = (now.timeIntervalSince1970 - entry.startTime) / (entry.endTime - entry.startTime)
                    GeometryReader { geometry in
                        Capsule().fill(focused ? .black.opacity(0.22) : .white.opacity(0.2))
                        Capsule().fill(focused ? Color(red: 0, green: 0.52, blue: 0.60) : .cyan)
                            .frame(width: geometry.size.width * elapsed)
                    }
                    .frame(height: IoDesign.Space.xSmall)
                }
            }
            .foregroundStyle(focused ? .black : .white)
            .padding(.horizontal, min(IoDesign.Space.medium, width / 4))
            .frame(width: width, height: IoDesign.scheduleRowHeight, alignment: .leading)
            .background(focused ? .white : .white.opacity(current ? 0.12 : 0.095), in: shape)
            .overlay {
                if isSelected && !focused {
                    shape.strokeBorder(.white.opacity(0.75), lineWidth: IoDesign.Space.xxSmall)
                }
            }
            .clipped()
        }
        .ioCustomButtonFocus()
        .focused($focus, equals: .row(row))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(channel.title), \(entry.timeRange), \(entry.title)\(entry.isRepeat ? ", kordus" : "")\(current ? ", praegu" : "")")
        .accessibilityHint(confirmedReplay(for: entry, at: now) != nil ? "Vaata järele" : "")
        .accessibilityIdentifier("telekava-\(channel.id)-\(entry.id)")
        .onMoveCommand { direction in
            move(direction, from: row)
        }
        .task(id: pendingRowFocus == row) {
            if pendingRowFocus == row {
                focus = .row(row)
                pendingRowFocus = nil
            }
        }
    }

    private func programmeDetail(_ entry: TelekavaEntry, channel: LiveChannel, now: Date) -> some View {
        let programme = catalogueDetail?.id == entry.contentId ? catalogueDetail : nil
        let status = entry.isCurrent(at: now) ? " · Praegu eetris" : ""
        return ProgrammeInfoCard(title: entry.title,
                                 metadata: "\(entry.timeRange) · \(channel.title)\(status)",
                                 lead: entry.lead, programme: programme)
    }

    private var selectedEntry: TelekavaEntry? {
        guard loadedDay == day, let selected else { return nil }
        return entries(for: selected.channelID).first { $0.id == selected.entryID }
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

    private func move(_ direction: MoveCommandDirection, from row: Row) {
        switch direction {
        case .left, .right:
            let programmes = entries(for: row.channelID)
            guard let index = programmes.firstIndex(where: { $0.id == row.entryID }) else { return }
            let target = index + (direction == .left ? -1 : 1)
            guard programmes.indices.contains(target) else { return }
            let entry = programmes[target]
            let now = Date.now
            let reference = entry.isCurrent(at: now) ? now.timeIntervalSince1970 : entry.startTime
            navigationTime = reference
            focusProgramme(entry, channelID: row.channelID, reference: reference)
        case .up, .down:
            moveBetweenChannels(direction, from: row.channelID)
        @unknown default:
            break
        }
    }

    private func moveBetweenChannels(_ direction: MoveCommandDirection, from channelID: String) {
        guard direction == .up || direction == .down,
              let index = LiveChannel.all.firstIndex(where: { $0.id == channelID }) else { return }
        let step = direction == .up ? -1 : 1
        var target = index + step
        let reference = navigationTime ?? windowStart
        while LiveChannel.all.indices.contains(target) {
            let channel = LiveChannel.all[target]
            if let entry = programme(on: channel.id, at: reference) {
                focusProgramme(entry, channelID: channel.id, reference: reference)
                return
            }
            if case .failed = schedules[channel.id] {
                focus = .retry(channel.id)
                return
            }
            target += step
        }
        if direction == .up {
            focus = .day(day)
        } else if let entry = selectedEntry, confirmedReplay(for: entry, at: .now) != nil {
            focus = .playbackAction
        }
    }

    private func programme(on channelID: String, at timestamp: TimeInterval) -> TelekavaEntry? {
        let programmes = entries(for: channelID)
        return programmes.first { $0.startTime <= timestamp && timestamp < $0.endTime }
            ?? programmes.min { distance(from: timestamp, to: $0) < distance(from: timestamp, to: $1) }
    }

    private func distance(from timestamp: TimeInterval, to entry: TelekavaEntry) -> TimeInterval {
        max(entry.startTime - timestamp, timestamp - entry.endTime, 0)
    }

    private func focusProgramme(_ entry: TelekavaEntry, channelID: String, reference: TimeInterval) {
        let row = Row(channelID: channelID, entryID: entry.id)
        selected = row
        if needsMoreRoom(entry) {
            placeWindow(around: min(max(reference, entry.startTime), entry.endTime), animated: true)
            pendingRowFocus = row
        } else {
            focus = .row(row)
        }
    }

    private func needsMoreRoom(_ entry: TelekavaEntry) -> Bool {
        let visibleDuration = min(entry.endTime, windowEnd) - max(entry.startTime, windowStart)
        return visibleDuration < min(entry.endTime - entry.startTime, 5 * 60)
    }

    private func placeWindow(around timestamp: TimeInterval, animated: Bool = false) {
        let earliest = LiveChannel.all.compactMap { entries(for: $0.id).first?.startTime }.min()
        let start = floor((timestamp - 2 * tickInterval) / tickInterval) * tickInterval
        let destination = max(start, floor((earliest ?? timestamp) / tickInterval) * tickInterval)
        let canSlide = animated && !reduceMotion && abs(destination - windowStart) <= windowDuration
        withAnimation(canSlide ? .easeInOut(duration: 0.24) : nil) {
            windowStart = destination
        }
    }

    private func playback(for entry: TelekavaEntry, channel: LiveChannel, now: Date) -> Playback? {
        if entry.isCurrent(at: now) { return .live(channel) }
        return confirmedReplay(for: entry, at: now).map(Playback.replay)
    }

    private func confirmedReplay(for entry: TelekavaEntry, at date: Date) -> Programme? {
        guard let catalogueDetail, catalogueDetail.hasVideo,
              catalogueDetail.id == entry.replayID(at: date) else { return nil }
        return catalogueDetail
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
        let previousSelection = loadedDay == requestedDay ? selected : nil
        let retryHadFocus: Bool
        if case .retry = focus { retryHadFocus = true } else { retryHadFocus = false }
        schedules = results
        loadedDay = requestedDay
        let preferredChannel = selected?.channelID ?? lastChannelID
        let channels = [preferredChannel] + LiveChannel.all.map(\.id).filter { $0 != preferredChannel }
        if let previousSelection,
           entries(for: previousSelection.channelID).contains(where: { $0.id == previousSelection.entryID }) {
            selected = previousSelection
        } else {
            selected = channels.lazy.compactMap { channelID in
                anchor(in: entries(for: channelID), now: now).map { Row(channelID: channelID, entryID: $0.id) }
            }.first
            navigationTime = selectedEntry.map { $0.isCurrent(at: now) ? now.timeIntervalSince1970 : $0.startTime }
            placeWindow(around: navigationTime ?? requestedDay.timeIntervalSince1970)
        }
        if pendingScheduleFocus == requestedDay {
            pendingScheduleFocus = nil
            if let selected {
                pendingRowFocus = selected
            } else {
                focusSchedule()
            }
        } else if (isInitialLoad && focus != nil) || retryHadFocus {
            pendingRowFocus = selected
        }
    }
}
