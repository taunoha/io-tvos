import SwiftUI
import UIKit

struct ProgrammeArtwork<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var loaded: (url: URL, image: UIImage)?

    var body: some View {
        Group {
            if let image = currentImage {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                loaded = nil
                return
            }
            guard loaded?.url != url else { return }
            loaded = nil
            guard let image = await ProgrammeArtworkCache.shared.image(for: url),
                  !Task.isCancelled else { return }
            loaded = (url, image)
        }
    }

    private var currentImage: UIImage? {
        guard let url else { return nil }
        if let loaded, loaded.url == url { return loaded.image }
        return ProgrammeArtworkCache.shared.cachedImage(for: url)
    }
}

@MainActor
private final class ProgrammeArtworkCache {
    static let shared = ProgrammeArtworkCache()

    private let images = NSCache<NSURL, UIImage>()
    private var pending: [URL: Task<UIImage?, Never>] = [:]

    private init() {
        images.totalCostLimit = 64 * 1024 * 1024
        images.countLimit = 200
    }

    func cachedImage(for url: URL) -> UIImage? {
        images.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let image = cachedImage(for: url) { return image }
        if let request = pending[url] { return await request.value }

        // Let the shared request finish when a scrolling view goes offscreen.
        let request = Task<UIImage?, Never> {
            defer { pending[url] = nil }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let source = UIImage(data: data) else { return nil }

            let image = await source.byPreparingForDisplay() ?? source
            if let pixels = image.cgImage {
                images.setObject(image, forKey: url as NSURL, cost: pixels.bytesPerRow * pixels.height)
            }
            return image
        }
        pending[url] = request
        return await request.value
    }
}
