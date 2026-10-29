import Foundation
import CryptoKit
import WasmKit
import Security

/// Seals a request via the bundled crush.wasm, POSTs to api.wing.st/g,
/// and AES-GCM-decrypts the response to extract the stream URL.
///
/// Protocol (reverse-engineered):
///   plaintext  = {"path":"/Nebula/movie|series","payload":{...}}
///   seal       = (in, in_len, ctx(44B), 44, out, out_cap) -> out_len
///   output     = [0:98]=header (AES key at [0:32]) | [98:]=wire
///   POST wire  = 200 OK, 203 bytes: [IV 12B][ct..][tag 16B]
///   decrypt    = AES-256-GCM with key=header[0:32], IV=resp[0:12], AAD=81B
enum NativeStreamResolver {

    private static let runtimeLock = NSLock()
    private static var cachedStore: Store?
    private static var cachedInstance: Instance?

    // MARK: - Public entry points

    static func resolveMovieStreamURL(
        tmdbID: Int, imdbID: String, year: String, title: String
    ) async throws -> URL {
        let plaintext = try buildPlaintext(
            path: "/Nebula/movie",
            fields: [
                "tmdb": String(tmdbID),
                "imdb": imdbID,
                "year": year,
                "title": title,
            ],
            fieldOrder: ["tmdb", "imdb", "year", "title"]
        )
        return try await sealPostDecrypt(plaintext: plaintext)
    }

    static func resolveTVStreamURL(
        tmdbID: Int, imdbID: String, year: String, title: String,
        season: Int, episode: Int
    ) async throws -> URL {
        let plaintext = try buildPlaintext(
            path: "/Nebula/series",
            fields: [
                "tmdb": String(tmdbID),
                "season": String(season),
                "episode": String(episode),
                "imdb": imdbID,
                "year": year,
                "title": title,
            ],
            fieldOrder: ["tmdb", "season", "episode", "imdb", "year", "title"]
        )
        return try await sealPostDecrypt(plaintext: plaintext)
    }

    // MARK: - Plaintext builder (field order matters to the server)

    private static func buildPlaintext(
        path: String,
        fields: [String: String],
        fieldOrder: [String]
    ) throws -> Data {
        let pairs = fieldOrder.compactMap { key -> String? in
            guard let value = fields[key] else { return nil }
            let esc = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(key)\":\"\(esc)\""
        }
        let payload = pairs.joined(separator: ",")
        let json = "{\"path\":\"\(path)\",\"payload\":{\(payload)}}"
        return Data(json.utf8)
    }

    // MARK: - Seal → POST → decrypt → extract

    private static func sealPostDecrypt(plaintext: Data) async throws -> URL {
        let (header, wire) = try seal(plaintext: plaintext)

        var req = URLRequest(url: URL(string: "https://api.wing.st/g")!)
        req.httpMethod = "POST"
        req.httpBody = wire
        req.setValue("text/plain;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30

        let (respData, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.badResponse(-1) }
        guard http.statusCode == 200 else { throw APIError.badResponse(http.statusCode) }
        guard respData.count >= 28 else { throw APIError.noResults }

        let key = header.prefix(32)
        let iv = respData.prefix(12)
        let body = respData.suffix(from: 12)
        guard body.count >= 16 else { throw APIError.noResults }
        let ct = body.prefix(body.count - 16)
        let tag = body.suffix(16)

        var aad = Data("lumen-gate-v2".utf8)
        aad.append(0x00)
        aad.append(contentsOf: wire.prefix(67))

        let symmetric = SymmetricKey(data: key)
        let nonce = try AES.GCM.Nonce(data: iv)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ct, tag: tag)
        let plaintextResp = try AES.GCM.open(sealedBox, using: symmetric, authenticating: aad)

        guard let json = try JSONSerialization.jsonObject(with: plaintextResp) as? [String: Any],
              let data = json["data"] as? [String: Any],
              let streams = data["stream"] as? [[String: Any]],
              let playlist = streams.first?["playlist"] as? String,
              let url = URL(string: playlist) else {
            throw APIError.noResults
        }
        return url
    }

    // MARK: - WASM seal

    private static func seal(plaintext: Data) throws -> (header: Data, wire: Data) {
        let (instance, _) = try getOrCreateInstance()
        let exports = instance.exports
        guard let memory = exports[memory: "memory"],
              let alloc = exports[function: "alloc"],
              let sealFn = exports[function: "seal_request"] else {
            throw APIError.missingConfiguration
        }

        var ctx = Data(count: 44)
        _ = ctx.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, 44, ptr.baseAddress!)
        }

        let inLen = UInt32(plaintext.count)
        let ctxLen: UInt32 = 44
        let outCap: UInt32 = 4096

        let inPtr = try alloc([.i32(inLen)])[0].i32
        let ctxPtr = try alloc([.i32(ctxLen)])[0].i32
        let outPtr = try alloc([.i32(outCap)])[0].i32
        guard inPtr > 0, ctxPtr > 0, outPtr > 0 else { throw APIError.missingConfiguration }

        writeMemory(memory, ptr: inPtr, data: plaintext)
        writeMemory(memory, ptr: ctxPtr, data: ctx)

        let result = try sealFn([
            .i32(inPtr), .i32(inLen),
            .i32(ctxPtr), .i32(ctxLen),
            .i32(outPtr), .i32(outCap),
        ])
        let outLen = Int(result[0].i32)
        guard outLen > 98 else {
            throw NSError(
                domain: "wasm.seal", code: outLen,
                userInfo: [NSLocalizedDescriptionKey: "seal_request returned \(outLen)"]
            )
        }

        let output = readMemory(memory, ptr: outPtr, len: outLen)
        return (output.prefix(98), output.suffix(from: 98))
    }

    private static func getOrCreateInstance() throws -> (Instance, Store) {
        runtimeLock.lock()
        defer { runtimeLock.unlock() }
        if let i = cachedInstance, let s = cachedStore { return (i, s) }
    
        guard let url = Bundle.main.url(forResource: "crush", withExtension: "wasm"),
              let data = try? Data(contentsOf: url) else {
            throw APIError.missingConfiguration
        }
    
        // --- FIX: Use parseWasm(bytes:) instead of Module(engine:bytes:) ---
        let engine = Engine()
        let store = Store(engine: engine)
        let module = try parseWasm(bytes: Array(data))
        let instance = try module.instantiate(store: store)
    
        cachedStore = store
        cachedInstance = instance
        return (instance, store)
    }

    private static func writeMemory(_ memory: Memory, ptr: UInt32, data: Data) {
        let buf = memory.data
        let base = Int(ptr)
        data.withUnsafeBytes { raw in
            let src = raw.bindMemory(to: UInt8.self)
            for i in 0..<data.count { buf[base + i] = src[i] }
        }
    }

    private static func readMemory(_ memory: Memory, ptr: UInt32, len: Int) -> Data {
        let buf = memory.data
        let base = Int(ptr)
        var out = Data(count: len)
        out.withUnsafeMutableBytes { raw in
            let dst = raw.bindMemory(to: UInt8.self)
            for i in 0..<len { dst[i] = buf[base + i] }
        }
        return out
    }
}
