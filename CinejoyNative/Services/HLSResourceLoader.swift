import Foundation
import AVFoundation

/// Intercepts AVPlayer's HLS requests, rewrites our custom scheme to https,
/// fetches the real content, and corrects the spoofed `image/jpeg` content-type.
///
/// Why: nebula.bright67.online serves valid HLS manifests AND fMP4 segments
/// with `content-type: image/jpeg` and image-looking file extensions
/// (playlist_000.jpg, playlist_001.png, etc.). AVPlayer refuses to parse
/// the manifest without this. The scheme trick guarantees we see every
/// request — AVPlayer resolves relative URLs against the base URL and
/// preserves the custom scheme.
final class HLSResourceLoader: NSObject, AVAssetResourceLoaderDelegate {

    static let scheme = "cinejoy-hls"
    private static var retainKey: UInt8 = 0

    static func wrapped(_ url: URL) -> URL {
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.scheme = Self.scheme
        return c?.url ?? url
    }

    static func asset(for url: URL) -> AVURLAsset {
        let asset = AVURLAsset(url: Self.wrapped(url))
        let loader = HLSResourceLoader()
        asset.resourceLoader.setDelegate(loader, queue: DispatchQueue(label: "hls.loader"))
        // AVAssetResourceLoader only holds its delegate weakly; tie the loader's
        // lifetime to the asset so it serves every segment, not just the manifest.
        objc_setAssociatedObject(asset, &Self.retainKey, loader, .OBJC_ASSOCIATION_RETAIN)
        return asset
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let wrappedURL = loadingRequest.request.url else { return false }
        var comps = URLComponents(url: wrappedURL, resolvingAgainstBaseURL: false)
        comps?.scheme = "https"
        guard let realURL = comps?.url else { return false }

        var req = URLRequest(url: realURL)
        req.setValue(
            "Mozilla/5.0 (AppleTV; tvOS 16.0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        req.setValue("https://cinejoy.pk/", forHTTPHeaderField: "Referer")
        req.setValue("*/*", forHTTPHeaderField: "Accept")

        if let dr = loadingRequest.dataRequest, !dr.requestsAllDataToEndOfResource {
            let start = dr.requestedOffset
            let end = start + Int64(dr.requestedLength) - 1
            req.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        }

        let task = URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                loadingRequest.finishLoading(with: error)
                return
            }
            guard let http = response as? HTTPURLResponse, let data = data else {
                loadingRequest.finishLoading(with: NSError(
                    domain: "HLSLoader", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "no response"]))
                return
            }

            let isManifest: Bool
            if data.count >= 7 {
                isManifest = data[0..<7] == Data([0x23, 0x45, 0x58, 0x54, 0x4d, 0x33, 0x55]) // "#EXTM3U"
            } else {
                isManifest = false
            }

            // Every non-manifest response on this CDN is fMP4 (segments + init.mp4),
            // regardless of the `.jpg` / `.png` / `.jpeg` extension.
            let realType = isManifest ? "application/vnd.apple.mpegurl" : "video/mp4"

            // For a 206 the body is already the requested range; the full
            // resource size comes from Content-Range ("bytes a-b/total").
            var totalLength = Int64(data.count)
            if http.statusCode == 206,
               let range = http.value(forHTTPHeaderField: "Content-Range"),
               let total = range.split(separator: "/").last.flatMap({ Int64($0) }) {
                totalLength = total
            }

            if let ci = loadingRequest.contentInformationRequest {
                ci.contentType = realType
                ci.contentLength = totalLength
                ci.isByteRangeAccessSupported = true
            }

            if let dr = loadingRequest.dataRequest {
                let start = Int(dr.requestedOffset)
                if http.statusCode != 206 && start > 0 && start < data.count {
                    dr.respond(with: data.subdata(in: start..<data.count))
                } else {
                    dr.respond(with: data)
                }
            }

            loadingRequest.finishLoading()
        }
        task.resume()
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        // Manifests/segments are tiny; task cancellation is unnecessary.
    }
}
