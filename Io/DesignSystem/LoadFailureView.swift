import SwiftUI

struct LoadFailureView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(message).font(.title3)
            Button("Proovi uuesti", action: retry)
        }
    }
}
