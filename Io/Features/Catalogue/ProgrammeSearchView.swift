import SwiftUI

struct ProgrammeSearchView: View {
    @FocusState private var focusedKey: String?
    @State private var phrase = ""
    @State private var resultRows: [[Programme]] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?
    @State private var refresh = 0
    private var query: String { phrase.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var requestKey: String { "\(query)|\(page)|\(refresh)" }
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            searchInput
                .padding(.horizontal, IoDesign.contentInset)
                .padding(.top, IoDesign.focusRoom)

            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        if query.isEmpty { Text("Sisesta saate või filmi nimi.").foregroundStyle(.secondary).padding(.horizontal, IoDesign.contentInset) }
                        ForEach(resultRows.indices, id: \.self) { index in
                            ProgrammeRow(
                                title: index == 0 ? "Otsingutulemused" : "Otsingutulemused · \(index + 1)",
                                items: resultRows[index]
                            )
                        }
                        if loading && page == 1 { ProgressView("Otsin…").padding(.horizontal, IoDesign.contentInset) }
                        if let error { LoadFailureView(message: error) { refresh += 1 }.padding(.horizontal, IoDesign.contentInset) }
                        if !loading && error == nil && !query.isEmpty && resultRows.isEmpty { Text("Tulemusi ei leitud.").padding(.horizontal, IoDesign.contentInset) }
                        if hasMore {
                            Button {
                                guard !loading else { return }
                                loading = true
                                page += 1
                            } label: {
                                HStack(spacing: 12) {
                                    Text("Laadi juurde")
                                    if loading {
                                        SearchLoadingSpinner()
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                            .accessibilityValue(loading ? "Laadin" : "")
                            .padding(.horizontal, IoDesign.contentInset)
                        }
                        Color.clear.frame(height: 1).id("searchResultsEnd")
                    }.padding(.vertical, IoDesign.focusRoom)
                }
                .onChange(of: loading) { wasLoading, isLoading in
                    if wasLoading && !isLoading && page > 1 {
                        scroll.scrollTo("searchResultsEnd", anchor: .bottom)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Keep shelves and their focus effects inside the results viewport.
            .clipped()
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .onChange(of: phrase) { _, _ in
            page = 1; resultRows = []; hasMore = false; error = nil
            loading = !query.isEmpty
        }
        .ignoresSafeArea(.container, edges: .horizontal)
        .task(id: requestKey) {
            let currentQuery = query
            let currentPage = page
            guard !currentQuery.isEmpty else { loading = false; return }
            loading = true; error = nil
            do {
                try await Task.sleep(for: .milliseconds(450))
                let batch = try await OnDemandAPI.search(currentQuery, page: currentPage)
                try Task.checkCancellation()
                guard currentQuery == query, currentPage == page else { return }
                var seen = Set(resultRows.flatMap { $0 }.map(\.id))
                let newResults = batch.filter { seen.insert($0.id).inserted }
                if !newResults.isEmpty { resultRows.append(newResults) }
                hasMore = batch.count == 24; loading = false
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = "Otsing ebaõnnestus. Proovi uuesti."; loading = false } }
        }
    }

    private var searchInput: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 24) {
                HStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                    Text(phrase.isEmpty ? "Otsi saadet või filmi" : phrase)
                        .foregroundStyle(phrase.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer(minLength: 0)
                }
                .font(IoDesign.body)
                .padding(18)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Otsing: \(phrase.isEmpty ? "tühi" : phrase)")

                Button("Tühik") { phrase.append(" ") }
                Button {
                    if !phrase.isEmpty { phrase.removeLast() }
                } label: {
                    Image(systemName: "delete.left")
                }
                .accessibilityLabel("Kustuta viimane märk")
                Button("Tühjenda") { phrase = "" }
            }

            // Ordinary buttons keep tvOS from opening its modal text editor.
            VStack(spacing: 12) {
                ForEach(["abcdefghijklmnopqrst", "uvwxyzõäöü0123456789"], id: \.self) { row in
                    HStack(spacing: 12) {
                        ForEach(Array(row), id: \.self) { character in
                            Button { phrase.append(String(character).lowercased()) } label: {
                                Text(String(character))
                                    .font(.system(size: 32, weight: .medium))
                                    .frame(width: 68, height: 52)
                                    .foregroundStyle(focusedKey == String(character) ? Color.black : Color.white)
                                    .background(focusedKey == String(character) ? Color.white : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .ioCustomButtonFocus()
                            .focused($focusedKey, equals: String(character))
                        }
                    }
                }
            }
        }
        .focusSection()
    }
}

private struct SearchLoadingSpinner: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let progress = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 0.8) / 0.8
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.foreground, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(progress * 360))
        }
        .frame(width: 22, height: 22)
        // Button focus/press transactions must not interpolate clock updates.
        .transaction { $0.animation = nil }
    }
}
