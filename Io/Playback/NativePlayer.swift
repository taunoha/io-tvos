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

    private final class InfoViewController: UIViewController {
        let hostingController: UIHostingController<InfoPanel>

        init(content: Info, height: CGFloat) {
            hostingController = UIHostingController(rootView: InfoPanel(content: content))
            super.init(nibName: nil, bundle: nil)
            title = "Info"
            preferredContentSize = CGSize(width: IoDesign.playerInfoWidth, height: height)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is unavailable")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            // Size the hosted content from the panel without feeding its layout back to AVKit.
            addChild(hostingController)
            let hostedView = hostingController.view!
            hostedView.frame = view.bounds
            hostedView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(hostedView)
            hostingController.didMove(toParent: self)
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
        controller.customInfoViewControllers = [InfoViewController(content: info(), height: infoHeight)]
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        context.coordinator.onDismiss = onDismiss
        if controller.player !== player { controller.player = player }
        let panel = controller.customInfoViewControllers.first as? InfoViewController
        panel?.hostingController.rootView = InfoPanel(content: info())
    }
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        controller.delegate = nil
        controller.player = nil
    }
}
