import SwiftUI
import UIKit

struct IoRootView: View {
    let history: WatchHistory
    let favorites: ProgrammeFavorites
    var body: some View {
        IoTabController(history: history, favorites: favorites)
            .ignoresSafeArea()
    }
}

/// UIKit's tvOS tab transition inserts snapshots into its tab content views.
/// Give every tab a UIKit-owned root rather than a UIHostingController root.
private struct IoTabController: UIViewControllerRepresentable {
    let history: WatchHistory
    let favorites: ProgrammeFavorites

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        weak var selectedTab: UIViewController?

        func open(_ programme: Programme, in controller: UITabBarController) {
            guard let tab = controller.viewControllers?.compactMap({ $0 as? IoTabContentController })
                .first(where: { $0.catalogueSource == programme.source }) else { return }
            tab.openProgramme?(programme)
            selectedTab = tab
            controller.selectedViewController = tab
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            guard selectedTab !== viewController else { return }
            selectedTab = viewController
            (viewController as? IoTabContentController)?.resetNavigation?()
        }
    }

    func makeUIViewController(context: Context) -> UITabBarController {
        let controller = UITabBarController()
        controller.view.tintColor = .white
        let coordinator = context.coordinator
        controller.viewControllers = [
            tab("Otse", image: "dot.radiowaves.left.and.right", content: LiveHomeView { [weak controller, weak coordinator] programme in
                guard let controller else { return }
                coordinator?.open(programme, in: controller)
            }),
            tab("Telekava", image: "calendar", content: TelekavaView()),
            tab("Saated", image: "play.rectangle.on.rectangle", content: CatalogueView(), catalogueSource: .jupiter),
            tab("Lasteekraan", image: "sparkles.tv", content: CatalogueView(source: .lasteekraan), catalogueSource: .lasteekraan),
            tab("Jätka", image: "clock.arrow.circlepath", content: ContinueWatchingView()),
            tab("Otsi", image: "magnifyingglass", content: ProgrammeSearchView(), resetsOnSelection: false)
        ]
        context.coordinator.selectedTab = controller.selectedViewController
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UITabBarController, context: Context) {}

    private func tab<Content: View>(_ title: String, image: String, content: Content,
                                    catalogueSource: CatalogueSource? = nil, resetsOnSelection: Bool = true) -> UIViewController {
        func rootView(programme: Programme? = nil) -> some View {
            IoTabNavigation(content: content, programme: programme)
                // Replacing the root explicitly resets local navigation and focus.
                .id(UUID())
                .environment(history)
                .environment(favorites)
                .tint(.white)
                .preferredColorScheme(.dark)
        }

        let host = UIHostingController(rootView: rootView())
        let tab = IoTabContentController(host: host, title: title, image: image, catalogueSource: catalogueSource)
        if resetsOnSelection {
            tab.resetNavigation = { [weak host] in host?.rootView = rootView() }
        }
        tab.openProgramme = { [weak host] programme in host?.rootView = rootView(programme: programme) }
        return tab
    }
}

private struct IoTabNavigation<Content: View>: View {
    let content: Content
    let programme: Programme?
    @State private var showsProgramme: Bool

    init(content: Content, programme: Programme?) {
        self.content = content
        self.programme = programme
        _showsProgramme = State(initialValue: programme != nil)
    }

    var body: some View {
        NavigationStack {
            content.navigationDestination(isPresented: $showsProgramme) {
                if let programme {
                    ProgrammeDetailView(programme: programme)
                }
            }
        }
    }
}

private final class IoTabContentController: UIViewController {
    private let host: UIViewController
    let catalogueSource: CatalogueSource?
    var resetNavigation: (() -> Void)?
    var openProgramme: ((Programme) -> Void)?

    init(host: UIViewController, title: String, image: String, catalogueSource: CatalogueSource?) {
        self.host = host
        self.catalogueSource = catalogueSource
        super.init(nibName: nil, bundle: nil)
        tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: image), selectedImage: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        addChild(host)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }
}
