import AVFoundation
import Foundation

struct PlaybackSource {
    let url: URL
    let fairPlay: FairPlayConfiguration?
    init(url: URL, fairPlay: FairPlayConfiguration? = nil) { self.url = url; self.fairPlay = fairPlay }
}

struct FairPlayConfiguration {
    let licenseURL: URL
    let refreshToken: () async throws -> String

    init(licenseAddress: String?, token: String?, refreshToken: @escaping () async throws -> String) throws {
        guard let address = licenseAddress, let url = URL(string: address),
              url.scheme == "https", url.host == "drm-fairplay-licensing.axprod.net",
              let token, !token.isEmpty else { throw FairPlayFailure.configuration }
        self.licenseURL = url
        self.refreshToken = refreshToken
    }
}

enum FairPlayFailure: LocalizedError {
    case simulatorUnsupported, configuration, certificate, identifier, request(Int), license(Int), invalidResponse
    var errorDescription: String? {
        switch self {
        case .simulatorUnsupported: return String(localized: "player.fairPlay.error.simulator")
        case .configuration: return String(localized: "player.fairPlay.error.configuration")
        case .certificate: return String(localized: "player.fairPlay.error.certificate")
        case .identifier: return String(localized: "player.fairPlay.error.identifier")
        case .request(let code): return String(localized: "player.fairPlay.error.request", defaultValue: "Seade ei saanud kaitstud video võtmetaotlust luua (\(code)).")
        case .license(let code): return String(localized: "player.fairPlay.error.license", defaultValue: "Videolitsentsi ei saanud väljastada (HTTP \(code)). Kontrolli sisu vaatamisõigust ja proovi uuesti.")
        case .invalidResponse: return String(localized: "player.fairPlay.error.invalidResponse")
        }
    }
}

private final class LicenseRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.host == task.originalRequest?.url?.host && request.url?.scheme == "https" ? request : nil)
    }
}

/// Uses ERR's application certificate and the entitlement token issued by ERR.
/// Keys are passed straight to AVFoundation; no persistent/offline keys are requested.
@MainActor
final class FairPlaySession: NSObject, AVContentKeySessionDelegate {
    private let keySession: AVContentKeySession
    private let configuration: FairPlayConfiguration
    private let onFailure: (String) -> Void
    private let network = URLSession(configuration: .ephemeral, delegate: LicenseRedirectDelegate(), delegateQueue: nil)
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var active = true
    private var asset: AVURLAsset?
    private static var certificate: Data?

    init(configuration: FairPlayConfiguration, asset: AVURLAsset, onFailure: @escaping (String) -> Void) throws {
        // AVFoundation raises an Objective-C exception on Simulator; Swift catch cannot handle it.
        #if targetEnvironment(simulator)
        throw FairPlayFailure.simulatorUnsupported
        #else
        self.keySession = AVContentKeySession(keySystem: .fairPlayStreaming)
        self.configuration = configuration
        self.onFailure = onFailure
        self.asset = asset
        super.init()
        keySession.setDelegate(self, queue: .main)
        keySession.addContentKeyRecipient(asset)
        #endif
    }

    nonisolated func contentKeySession(_ session: AVContentKeySession, didProvide keyRequest: AVContentKeyRequest) {
        Task { @MainActor [weak self] in self?.handle(keyRequest) }
    }
    nonisolated func contentKeySession(_ session: AVContentKeySession, didProvideRenewingContentKeyRequest keyRequest: AVContentKeyRequest) {
        Task { @MainActor [weak self] in self?.handle(keyRequest) }
    }
    nonisolated func contentKeySession(_ session: AVContentKeySession, contentKeyRequest keyRequest: AVContentKeyRequest, didFailWithError err: Error) {
        let code = (err as NSError).code
        Task { @MainActor [weak self] in
            guard let self, self.active else { return }
            self.onFailure(FairPlayFailure.request(code).localizedDescription)
        }
    }

    private func handle(_ request: AVContentKeyRequest) {
        guard active else { return }
        checkpoint("key-request")
        let id = ObjectIdentifier(request)
        guard tasks[id] == nil else { return }
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            defer { self.tasks[id] = nil }
            do {
                let identifier = (request.identifier as? String) ?? (request.identifier as? URL)?.absoluteString
                guard let identifier, identifier.hasPrefix("skd://"),
                      let contentID = String(identifier.dropFirst(6)).data(using: .utf8), !contentID.isEmpty else { throw FairPlayFailure.identifier }
                let certificate = try await self.applicationCertificate()
                self.checkpoint("certificate-ready")
                try Task.checkCancellation()
                let spc: Data = try await withCheckedThrowingContinuation { continuation in
                    request.makeStreamingContentKeyRequestData(forApp: certificate, contentIdentifier: contentID,
                        options: [AVContentKeyRequestProtocolVersionsKey: [1]]) { data, error in
                        if let data { continuation.resume(returning: data) }
                        else { continuation.resume(throwing: FairPlayFailure.request((error as NSError?)?.code ?? 0)) }
                    }
                }
                try Task.checkCancellation()
                // A fresh token is obtained for renewals and key rotation too.
                self.checkpoint("spc-ready")
                let token = try await self.configuration.refreshToken()
                var licenseRequest = URLRequest(url: self.configuration.licenseURL)
                licenseRequest.httpMethod = "POST"
                licenseRequest.timeoutInterval = 20
                licenseRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                licenseRequest.setValue(token, forHTTPHeaderField: "X-AxDRM-Message")
                licenseRequest.httpBody = spc
                let (ckc, response) = try await self.network.data(for: licenseRequest)
                try Task.checkCancellation()
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                self.checkpoint("license-http-\(code)")
                guard code == 200 else { throw FairPlayFailure.license(code) }
                guard !ckc.isEmpty, ckc.count < 1_048_576 else { throw FairPlayFailure.invalidResponse }
                guard self.active else { return }
                request.processContentKeyResponse(AVContentKeyResponse(fairPlayStreamingKeyResponseData: ckc))
                self.checkpoint("key-response-delivered")
            } catch is CancellationError { }
            catch {
                guard self.active, !Task.isCancelled else { return }
                let failure = (error as? FairPlayFailure) ?? .invalidResponse
                self.checkpoint("failed-\((error as NSError).code)")
                request.processContentKeyResponseError(failure)
                self.onFailure(failure.localizedDescription)
            }
        }
    }

    private func applicationCertificate() async throws -> Data {
        if let cached = Self.certificate { return cached }
        var request = URLRequest(url: URL(string: "https://jupiter.err.ee/fairplay.cer")!)
        request.timeoutInterval = 15
        let (data, response) = try await network.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty, data.count < 65_536 else { throw FairPlayFailure.certificate }
        Self.certificate = data
        return data
    }

    private func checkpoint(_ stage: String) {
        #if DEBUG
        let defaults = UserDefaults.standard
        var events = defaults.stringArray(forKey: "fairplay-debug-events") ?? []
        events.append(Date().ISO8601Format() + " " + stage)
        defaults.set(Array(events.suffix(32)), forKey: "fairplay-debug-events")
        #endif
    }

    func stop() {
        guard active else { return }
        active = false
        tasks.values.forEach { $0.cancel() }; tasks.removeAll()
        keySession.setDelegate(nil, queue: nil)
        if let asset { keySession.removeContentKeyRecipient(asset) }
        keySession.expire()
        asset = nil
        network.invalidateAndCancel()
    }
}
