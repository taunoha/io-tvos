import SwiftUI

@main
struct IoApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var history = WatchHistory()
    @State private var favorites = ProgrammeFavorites()

    var body: some Scene {
        WindowGroup {
            let deadline = history.nextReplayDeadline
            IoRootView(history: history, favorites: favorites)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { history.updateAvailability() }
                }
                .task(id: deadline) {
                    guard let deadline else { return }
                    do {
                        try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
                        history.updateAvailability()
                    } catch { }
                }
        }
    }
}
