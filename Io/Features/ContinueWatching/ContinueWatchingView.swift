import SwiftUI

struct ContinueWatchingView: View {
    @Environment(WatchHistory.self) private var history
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IoDesign.shelfGap) {
                Text(String(localized: "continueWatching.title")).font(IoDesign.pageTitle).padding(.horizontal, IoDesign.contentInset)
                if history.inProgress.isEmpty {
                    Text(String(localized: "continueWatching.empty")).font(IoDesign.body).foregroundStyle(.secondary).padding(.horizontal, IoDesign.contentInset)
                } else {
                    ProgrammeRow(title: String(localized: "continueWatching.shelf"), items: history.inProgress.map(\.programme), allowsRemovingProgress: true, wrapsCards: true)
                }
            }.padding(.vertical, IoDesign.focusRoom)
        }
        .scrollClipDisabled()
        .ignoresSafeArea(.container, edges: .horizontal)
    }
}
