import SwiftUI

struct ProgrammeFavoriteButton: View {
    @Environment(ProgrammeFavorites.self) private var favorites
    let favorite: ProgrammeFavorite

    var body: some View {
        let isFavorite = favorites.contains(favorite)
        Button(isFavorite ? String(localized: "detail.removeFavorite") : String(localized: "detail.addFavorite"),
               systemImage: isFavorite ? "star.fill" : "star") {
            favorites.toggle(favorite)
        }
    }
}
