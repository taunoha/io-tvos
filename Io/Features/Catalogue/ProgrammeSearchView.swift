import SwiftUI

@Observable
final class ProgrammeSearchNavigation {
    var selectedProgrammeID: Int?
}

struct ProgrammeSearchView: View {
    private struct Request: Equatable {
        let query: String
        let page: Int
        private let id = UUID()
    }

    let navigation: ProgrammeSearchNavigation
    @FocusState private var focusedKey: String?
    @State private var phrase = ""
    @State private var results: [Programme] = []
    @State private var seenIDs: Set<Int> = []
    @State private var nextPage: Int?
    @State private var request: Request?
    @State private var failedPage: Int?

    private var query: String { phrase.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        @Bindable var navigation = navigation
        VStack(alignment: .leading, spacing: IoDesign.shelfGap) {
            searchInput
                .padding(.horizontal, IoDesign.contentInset)
                .padding(.top, IoDesign.focusRoom)

            ScrollView {
                VStack(alignment: .leading, spacing: IoDesign.shelfGap) {
                    if !results.isEmpty {
                        ProgrammeRow(title: "Otsingutulemused", items: results, wrapsCards: true, openProgramme: { programme in
                            navigation.selectedProgrammeID = programme.id
                        })
                            .overlay(alignment: .bottom) {
                                if let nextPage {
                                    paginationTrigger(for: nextPage)
                                }
                            }
                    }
                    searchStatus
                        .padding(.horizontal, IoDesign.contentInset)
                }
                .padding(.vertical, IoDesign.focusRoom)
            }
            .id(query)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Keep cards and their focus effects inside the results viewport.
            .clipped()
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .ignoresSafeArea(.container, edges: .horizontal)
        .navigationDestination(item: $navigation.selectedProgrammeID) { id in
            if let programme = results.first(where: { $0.id == id }) {
                ProgrammeDetailView(programme: programme)
            }
        }
        .onChange(of: query) { _, query in
            results = []
            seenIDs = []
            nextPage = nil
            failedPage = nil
            request = query.isEmpty ? nil : Request(query: query, page: 1)
        }
        .task(id: request) { [request] in
            if let request {
                await load(request)
            }
        }
    }

    @ViewBuilder
    private var searchStatus: some View {
        if query.isEmpty {
            Text("Sisesta saate või filmi nimi.").foregroundStyle(.secondary)
        } else if let failedPage {
            LoadFailureView(message: "Otsing ebaõnnestus. Proovi uuesti.") {
                request = Request(query: query, page: failedPage)
                self.failedPage = nil
            }
        } else if let request {
            ProgressView(request.page == 1 ? "Otsin…" : "Laadin tulemusi…")
        } else if results.isEmpty {
            Text("Tulemusi ei leitud.")
        }
    }

    private func paginationTrigger(for page: Int) -> some View {
        // Start loading while the final row is still coming into view.
        Color.clear
            .frame(height: IoDesign.landscapeCardWidth)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onScrollVisibilityChange(threshold: 0.1) { visible in
                guard visible, nextPage == page, request == nil, failedPage == nil else { return }
                request = Request(query: query, page: page)
            }
            .id(page)
    }

    private func load(_ current: Request) async {
        do {
            if current.page == 1 {
                try await Task.sleep(for: .milliseconds(450))
            }
            let batch = try await OnDemandAPI.search(current.query, page: current.page)
            try Task.checkCancellation()
            guard request == current, query == current.query else { return }

            var seen = seenIDs
            let additions = batch.programmes.filter { seen.insert($0.id).inserted }
            seenIDs = seen
            results.append(contentsOf: additions)
            nextPage = batch.hasMore ? current.page + 1 : nil
            request = nil
        } catch {
            guard !Task.isCancelled, request == current, query == current.query else { return }
            failedPage = current.page
            request = nil
        }
    }

    private var searchInput: some View {
        VStack(alignment: .leading, spacing: IoDesign.Space.large) {
            HStack(spacing: IoDesign.Space.large) {
                HStack(spacing: IoDesign.Space.medium) {
                    Image(systemName: "magnifyingglass")
                    Text(phrase.isEmpty ? "Otsi saadet või filmi" : phrase)
                        .foregroundStyle(phrase.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer(minLength: 0)
                }
                .font(IoDesign.body)
                .padding(IoDesign.Space.large)
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
            VStack(spacing: IoDesign.Space.medium) {
                ForEach(["abcdefghijklmnopqrst", "uvwxyzõäöü0123456789"], id: \.self) { row in
                    HStack(spacing: IoDesign.Space.medium) {
                        ForEach(Array(row), id: \.self) { character in
                            Button { phrase.append(String(character).lowercased()) } label: {
                                Text(String(character))
                                    .font(IoDesign.body.weight(.medium))
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
