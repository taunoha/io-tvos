import SwiftUI

struct LoadFailureView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: IoDesign.Space.large) {
            Text(message).font(IoDesign.body)
            Button("Proovi uuesti", action: retry)
        }
    }
}
