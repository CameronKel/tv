import Foundation
import CryptoKit
import WasmKit
import Security

enum NativeStreamResolver {

    private static let runtimeLock = NSLock()
    private static var cachedRuntime: Runtime?
    private static var cachedInstance: ModuleInstance?

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

    // MARK: - Plaintext builder

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

    // MARK: - Seal → POST → decrypt

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

    // MARK: - WASM seal (WasmKit 0.0.8)

    private static func seal(plaintext: Data) throws -> (header: Data, wire: Data) {
        let (runtime, instance) = try getOrCreateInstance()

        guard case let .memory(memory)? = instance.exports["memory"] else {
            throw APIError.missingConfiguration
        }

        var ctx = Data(count: 44)
        _ = ctx.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, 44, ptr.baseAddress!)
        }

        let inLen = UInt32(plaintext.count)
        let ctxLen: UInt32 = 44
        let outCap: UInt32 = 4096

        let inPtr = try runtime.invoke(
            instance, function: "alloc", with: [.i32(inLen)]
        )[0].i32
        let ctxPtr = try runtime.invoke(
            instance, function: "alloc", with: [.i32(ctxLen)]
        )[0].i32
        let outPtr = try runtime.invoke(
            instance, function: "alloc", with: [.i32(outCap)]
        )[0].i32

        guard inPtr > 0, ctxPtr > 0, outPtr > 0 else {
            throw APIError.missingConfiguration
        }

        writeMemory(runtime, memory, ptr: inPtr, data: plaintext)
        writeMemory(runtime, memory, ptr: ctxPtr, data: ctx)

        let result = try runtime.invoke(instance, function: "seal_request", with: [
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

        let output = readMemory(runtime, memory, ptr: outPtr, len: outLen)
        return (output.prefix(98), output.suffix(from: 98))
    }

    private static func getOrCreateInstance() throws -> (Runtime, ModuleInstance) {
        runtimeLock.lock()
        defer { runtimeLock.unlock() }
        if let r = cachedRuntime, let i = cachedInstance { return (r, i) }

        guard let url = Bundle.main.url(forResource: "crush", withExtension: "wasm"),
              let data = try? Data(contentsOf: url) else {
            throw APIError.missingConfiguration
        }

        let module = try parseWasm(bytes: Array(data))
        let runtime = Runtime()
        let instance = try runtime.instantiate(module: module)

        cachedRuntime = runtime
        cachedInstance = instance
        return (runtime, instance)
    }

    private static func writeMemory(
        _ runtime: Runtime, _ memory: MemoryAddress, ptr: UInt32, data: Data
    ) {
        let base = Int(ptr)
        runtime.store.withMemory(at: memory) { mem in
            for (i, byte) in data.enumerated() {
                mem.data[base + i] = byte
            }
        }
    }

    private static func readMemory(
        _ runtime: Runtime, _ memory: MemoryAddress, ptr: UInt32, len: Int
    ) -> Data {
        let base = Int(ptr)
        return runtime.store.withMemory(at: memory) { mem in
            Data(mem.data[base..<(base + len)])
        }
    }
}
