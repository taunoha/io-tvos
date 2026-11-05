import SwiftUI

@main
struct IoApp: App {
    @State private var history = WatchHistory()
    @State private var favorites = ProgrammeFavorites()

    var body: some Scene {
        WindowGroup { IoRootView(history: history, favorites: favorites).preferredColorScheme(.dark) }
    }
}
