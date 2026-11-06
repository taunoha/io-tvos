import SwiftUI
import AVKit

struct NativePlayer<Info: View>: UIViewControllerRepresentable {
    let player: AVPlayer
    let onDismiss: () -> Void
    var infoHeight: CGFloat = IoDesign.playerInfoHeight
    @ViewBuilder let info: () -> Info

    private struct InfoPanel: View {
        let content: Info

        var body: some View {
            content
                .padding(.horizontal, IoDesign.playerInfoHorizontalInset)
                .frame(maxHeight: .infinity)
        }
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }
        func playerViewControllerShouldDismiss(_ playerViewController: AVPlayerViewController) -> Bool {
            onDismiss()
            return false // SwiftUI owns the presentation; dismiss its cover explicitly.
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.delegate = context.coordinator
        controller.showsPlaybackControls = true
        let panel = UIHostingController(rootView: InfoPanel(content: info()))
        panel.title = "Info"
        panel.preferredContentSize = CGSize(width: IoDesign.playerInfoWidth, height: infoHeight)
        controller.customInfoViewControllers = [panel]
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        context.coordinator.onDismiss = onDismiss
        if controller.player !== player { controller.player = player }
        let panel = controller.customInfoViewControllers.first as? UIHostingController<InfoPanel>
        panel?.rootView = InfoPanel(content: info())
    }
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        controller.delegate = nil
        controller.player = nil
    }
}
