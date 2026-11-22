import SwiftUI
import AVKit

struct NativePlayer<Info: View>: UIViewControllerRepresentable {
    let player: AVPlayer
    let onDismiss: () -> Void
    var infoHeight: CGFloat = IoDesign.playerInfoHeight
    var additionalTab: NativePlayerTab? = nil
    var onDetach: (() -> Void)? = nil
    @ViewBuilder let info: () -> Info

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var onDismiss: () -> Void
        var isClosingPanel = false
        var onDetach: (() -> Void)?

        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }

        func playerViewControllerShouldDismiss(_ playerViewController: AVPlayerViewController) -> Bool {
            onDismiss()
            return false // SwiftUI owns the presentation; dismiss its cover explicitly.
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        context.coordinator.onDetach = onDetach
        controller.player = player
        controller.delegate = context.coordinator
        controller.showsPlaybackControls = true
        controller.customInfoViewControllers = [PlayerInfoPanelController(title: String(localized: "player.infoTab"), content: info(), height: infoHeight)]
        updatePanels(controller, coordinator: context.coordinator)
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        context.coordinator.onDismiss = onDismiss
        if controller.player !== player { controller.player = player }
        updatePanels(controller, coordinator: context.coordinator)
    }

    private func updatePanels(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        guard let infoPanel = controller.customInfoViewControllers.first as? PlayerInfoPanelController<Info> else { return }
        infoPanel.hostingController.rootView = PlayerInfoPanel(content: info())
        let existing = controller.customInfoViewControllers.dropFirst().first as? PlayerInfoPanelController<AnyView>
        guard let additionalTab else {
            if existing != nil { controller.customInfoViewControllers = [infoPanel] }
            return
        }
        let panel = existing ?? PlayerInfoPanelController(
            title: additionalTab.title, content: AnyView(EmptyView()), height: additionalTab.height
        )
        let content = additionalTab.content { [weak panel, weak controller, weak coordinator] completion in
            guard let panel, let controller, let coordinator, !coordinator.isClosingPanel else { return }
            guard let presentation = panel.infoPresentation(over: controller) else {
                completion()
                return
            }
            coordinator.isClosingPanel = true
            presentation.dismiss(animated: false) { [weak controller, weak coordinator] in
                guard let controller, controller.player != nil, let coordinator else { return }
                coordinator.isClosingPanel = false
                completion()
            }
        }
        panel.hostingController.rootView = PlayerInfoPanel(content: content)
        if existing == nil {
            controller.customInfoViewControllers = [infoPanel, panel]
        }
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        controller.delegate = nil
        controller.player = nil
        coordinator.onDetach?()
    }
}

struct NativePlayerTab {
    let title: String
    let height: CGFloat
    let content: (@escaping (@escaping () -> Void) -> Void) -> AnyView
}

private struct PlayerInfoPanel<Content: View>: View {
    let content: Content

    var body: some View {
        content
            .padding(.horizontal, IoDesign.playerInfoHorizontalInset)
            .frame(maxHeight: .infinity)
    }
}

private final class PlayerInfoPanelController<Content: View>: UIViewController {
    let hostingController: UIHostingController<PlayerInfoPanel<Content>>

    init(title: String, content: Content, height: CGFloat) {
        hostingController = UIHostingController(rootView: PlayerInfoPanel(content: content))
        super.init(nibName: nil, bundle: nil)
        self.title = title
        preferredContentSize = CGSize(width: IoDesign.playerInfoWidth, height: height)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func infoPresentation(over player: AVPlayerViewController) -> UIViewController? {
        var ancestor: UIViewController? = self
        while let candidate = ancestor, candidate !== player {
            if let presenter = candidate.presentingViewController,
               presenter.presentedViewController === candidate,
               let presentationView = candidate.viewIfLoaded,
               let playerView = player.viewIfLoaded,
               !playerView.isDescendant(of: presentationView) {
                return candidate
            }
            ancestor = candidate.parent
        }
        return nil
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
