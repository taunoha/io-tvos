import SwiftUI
import AVKit

struct NativePlayer<Info: View>: UIViewControllerRepresentable {
    let player: AVPlayer
    let onDismiss: () -> Void
    var infoHeight: CGFloat = IoDesign.playerInfoHeight
    var additionalTab: NativePlayerTab? = nil
    @ViewBuilder let info: () -> Info

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var onDismiss: () -> Void
        var restoreControls: Task<Void, Never>?
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
        let content = additionalTab.content { [weak controller, weak coordinator] in
            guard let controller, let coordinator else { return }
            controller.showsPlaybackControls = false
            coordinator.restoreControls?.cancel()
            coordinator.restoreControls = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                controller.showsPlaybackControls = true
            }
        }
        if let existing {
            existing.hostingController.rootView = PlayerInfoPanel(content: content)
        } else {
            let panel = PlayerInfoPanelController(title: additionalTab.title, content: content, height: additionalTab.height)
            controller.customInfoViewControllers = [infoPanel, panel]
        }
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.restoreControls?.cancel()
        controller.delegate = nil
        controller.player = nil
    }
}

struct NativePlayerTab {
    let title: String
    let height: CGFloat
    let content: (@escaping () -> Void) -> AnyView
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
