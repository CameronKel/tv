import Foundation
import AVFoundation

/// Serves HLS playlists to AVPlayer and fixes up the CDN's quirks.
///
/// Why: nebula.bright67.online serves valid HLS playlists with
/// `content-type: image/jpeg` and image-looking names (`master.m3u8` points at
/// `720p/playlist.jpg`). AVPlayer refuses those playlists, so we fetch them
/// ourselves through a custom scheme.
///
/// AVFoundation only lets a resource loader supply HLS *playlists* (and keys),
/// never media segments. So every playlist is rewritten: URIs of other
/// playlists keep the custom scheme (we see and fix those too), while segment,
/// init-map and key URIs become absolute https URLs that AVPlayer loads itself.
final class HLSResourceLoader: NSObject, AVAssetResourceLoaderDelegate {

    static let scheme = "cinejoy-hls"
    private static var retainKey: UInt8 = 0

    static let httpHeaders = [
        "User-Agent": "Mozilla/5.0 (AppleTV; tvOS 16.0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15",
        "Referer": "https://cinejoy.pk/",
    ]

    static func wrapped(_ url: URL) -> URL {
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.scheme = Self.scheme
        return c?.url ?? url
    }

    static func unwrapped(_ url: URL) -> URL? {
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.scheme = "https"
        return c?.url
    }

    /// Where playback will start, so AVPlayer buffers from there.
    private let startOffset: Double

    private init(startOffset: Double) {
        self.startOffset = startOffset
    }

    static func asset(for url: URL, startingAt startOffset: Double = 0) -> AVURLAsset {
        // Headers for the segment requests AVPlayer makes on its own.
        let asset = AVURLAsset(
            url: Self.wrapped(url),
            options: ["AVURLAssetHTTPHeaderFieldsKey": Self.httpHeaders]
        )
        let loader = HLSResourceLoader(startOffset: startOffset)
        asset.resourceLoader.setDelegate(loader, queue: DispatchQueue(label: "hls.loader"))
        // AVAssetResourceLoader only holds its delegate weakly; tie the loader's
        // lifetime to the asset so it serves every playlist, not just the first.
        objc_setAssociatedObject(asset, &Self.retainKey, loader, .OBJC_ASSOCIATION_RETAIN)
        return asset
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let wrappedURL = loadingRequest.request.url,
              wrappedURL.scheme == Self.scheme,
              let realURL = Self.unwrapped(wrappedURL) else { return false }

        var req = URLRequest(url: realURL)
        for (field, value) in Self.httpHeaders {
            req.setValue(value, forHTTPHeaderField: field)
        }
        req.setValue("*/*", forHTTPHeaderField: "Accept")

        let task = URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                loadingRequest.finishLoading(with: error)
                return
            }
            guard let http = response as? HTTPURLResponse, let data = data else {
                loadingRequest.finishLoading(with: Self.error("no response for \(realURL.lastPathComponent)"))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                loadingRequest.finishLoading(with: Self.error(
                    "HTTP \(http.statusCode) for \(realURL.lastPathComponent)"))
                return
            }
            guard let text = String(data: data, encoding: .utf8), text.hasPrefix("#EXTM3U") else {
                loadingRequest.finishLoading(with: Self.error(
                    "\(realURL.lastPathComponent) is not an HLS playlist"))
                return
            }

            // Resolve relative URIs against the final URL, after any redirects.
            let playlist = Data(Self.rewrite(text, base: http.url ?? realURL,
                                             startOffset: self.startOffset).utf8)
            loadingRequest.contentInformationRequest?.contentLength = Int64(playlist.count)
            loadingRequest.contentInformationRequest?.isByteRangeAccessSupported = false
            loadingRequest.dataRequest?.respond(with: playlist)
            loadingRequest.finishLoading()
        }
        task.resume()
        return true
    }

    // MARK: - Playlist rewriting

    /// Makes every URI absolute. A master playlist's URIs are other playlists,
    /// so they stay on our scheme; a media playlist's are segments, the init
    /// map and keys, which AVPlayer must fetch directly over https.
    ///
    /// A resume point goes into the master playlist as `EXT-X-START`, so
    /// AVPlayer loads segments from there instead of buffering the opening
    /// and then seeking away from it.
    static func rewrite(_ playlist: String, base: URL, startOffset: Double = 0) -> String {
        let isMaster = playlist.contains("#EXT-X-STREAM-INF")
            || playlist.contains("#EXT-X-I-FRAME-STREAM-INF")
        let resolve = { (uri: String) -> String in
            guard let abs = URL(string: uri, relativeTo: base)?.absoluteURL else { return uri }
            return (isMaster ? Self.wrapped(abs) : abs).absoluteString
        }

        var lines = playlist.components(separatedBy: .newlines).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return line }
            if trimmed.hasPrefix("#") { return rewriteURIAttribute(in: line, resolve) }
            return resolve(trimmed)
        }
        if isMaster, startOffset > 0, !playlist.contains("#EXT-X-START") {
            lines.insert("#EXT-X-START:TIME-OFFSET=\(Int(startOffset)),PRECISE=YES", at: 1)
        }
        return lines.joined(separator: "\n")
    }

    private static let uriAttribute = try! NSRegularExpression(pattern: #"URI="([^"]*)""#)

    /// Rewrites the `URI="…"` attribute of tags such as EXT-X-MAP, EXT-X-KEY
    /// and EXT-X-MEDIA.
    private static func rewriteURIAttribute(in line: String, _ resolve: (String) -> String) -> String {
        let ns = line as NSString
        guard let match = uriAttribute.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))
        else { return line }
        let uri = ns.substring(with: match.range(at: 1))
        return ns.replacingCharacters(in: match.range, with: "URI=\"\(resolve(uri))\"")
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "HLSLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
