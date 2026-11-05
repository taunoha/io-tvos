import SwiftUI

struct CatalogueView: View {
    var source: CatalogueSource = .jupiter
    @State private var shelves: [ProgrammeShelf] = []
    @State private var error: String?
    @State private var loading = true
    @State private var refresh = 0
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: IoDesign.shelfGap) {
                Text(source.title).font(IoDesign.pageTitle).padding(.horizontal, IoDesign.contentInset)
                if loading { ProgressView("Laadin saateid…").padding(.horizontal, IoDesign.contentInset).padding(.vertical, IoDesign.focusRoom) }
                if let error { LoadFailureView(message: error) { refresh += 1 }.padding(.horizontal, IoDesign.contentInset) }
                if !loading && error == nil && shelves.isEmpty { Text("Saateid pole praegu kuvada.").padding(.horizontal, IoDesign.contentInset).padding(.vertical, IoDesign.focusRoom) }
                ForEach(shelves) { ProgrammeRow(title: $0.title, items: $0.programmes, usesPortraitCards: $0.usesPortraitCards) }
            }.padding(.vertical, IoDesign.focusRoom)
        }
        .scrollClipDisabled()
        .ignoresSafeArea(.container, edges: .horizontal)
        .task(id: refresh) {
            loading = true; error = nil
            do { let result = try await OnDemandAPI.catalogue(source: source); try Task.checkCancellation(); shelves = result; loading = false }
            catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = "Saateid ei saanud laadida. Kontrolli ühendust ja proovi uuesti."; loading = false } }
        }
    }
}
