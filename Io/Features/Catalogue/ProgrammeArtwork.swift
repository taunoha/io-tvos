import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct ProgrammeArtwork<Placeholder: View>: View {
    let url: URL?
    var usesPortraitFrame = false
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var loaded: (url: URL, artwork: LoadedProgrammeArtwork)?

    var body: some View {
        Group {
            if let artwork = currentArtwork {
                let image = Image(uiImage: artwork.image).resizable()
                if !usesPortraitFrame && artwork.isPortrait {
                    let tint = artwork.tint ?? .gray
                    LinearGradient(colors: [tint.opacity(0.5), tint.opacity(0.2)], startPoint: .top, endPoint: .bottom)
                        .background(.black)
                        .overlay { image.scaledToFit() }
                } else {
                    image.scaledToFill()
                }
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
            guard let artwork = await ProgrammeArtworkCache.shared.artwork(for: url),
                  !Task.isCancelled else { return }
            loaded = (url, artwork)
        }
    }

    private var currentArtwork: LoadedProgrammeArtwork? {
        guard let url else { return nil }
        if let loaded, loaded.url == url { return loaded.artwork }
        return ProgrammeArtworkCache.shared.cachedArtwork(for: url)
    }
}

@MainActor
private final class LoadedProgrammeArtwork {
    let image: UIImage
    var isPortrait: Bool { image.size.height > image.size.width }

    init(image: UIImage) {
        self.image = image
    }

    lazy var tint: Color? = {
        guard let input = CIImage(image: image), !input.extent.isEmpty else { return nil }
        let filter = CIFilter.areaAverage()
        filter.inputImage = input
        filter.extent = input.extent
        guard let average = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        Self.colorContext.render(average, toBitmap: &pixel, rowBytes: 4, bounds: average.extent,
            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return Color(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }()

    private static let colorContext = CIContext()
}

@MainActor
private final class ProgrammeArtworkCache {
    static let shared = ProgrammeArtworkCache()

    private let images = NSCache<NSURL, LoadedProgrammeArtwork>()
    private var pending: [URL: Task<LoadedProgrammeArtwork?, Never>] = [:]

    private init() {
        images.totalCostLimit = 64 * 1024 * 1024
        images.countLimit = 200
    }

    func cachedArtwork(for url: URL) -> LoadedProgrammeArtwork? {
        images.object(forKey: url as NSURL)
    }

    func artwork(for url: URL) async -> LoadedProgrammeArtwork? {
        if let artwork = cachedArtwork(for: url) { return artwork }
        if let request = pending[url] { return await request.value }

        // Let the shared request finish when a scrolling view goes offscreen.
        let request = Task<LoadedProgrammeArtwork?, Never> {
            defer { pending[url] = nil }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let source = UIImage(data: data) else { return nil }

            let image = await source.byPreparingForDisplay() ?? source
            let artwork = LoadedProgrammeArtwork(image: image)
            if let pixels = image.cgImage {
                images.setObject(artwork, forKey: url as NSURL, cost: pixels.bytesPerRow * pixels.height)
            }
            return artwork
        }
        pending[url] = request
        return await request.value
    }
}
