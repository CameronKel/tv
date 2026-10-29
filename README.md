# Cinejoy Native (tvOS)

Native tvOS client for cinejoy.pk — SwiftUI UI, AVPlayer playback, 
WASM-based request sealing, AES-GCM response decryption, HLS loader for 
content-type-spoofed CDN segments.

**No proxy, no laptop, no Python at runtime.** Everything runs on the Apple TV.

## Architecture

```
User taps Play
  ↓
NativeStreamResolver
  ├─ build 103/134-byte JSON plaintext (movie / TV)
  ├─ seal via bundled crush.wasm (WasmKit)      → header + wire
  ├─ POST wire to https://api.wing.st/g         → 200, 203 bytes
  └─ AES-256-GCM decrypt (CryptoKit)            → m3u8 URL
  ↓
HLSResourceLoader (AVAssetResourceLoaderDelegate)
  ├─ intercepts every playlist (served as image/jpeg, so AVPlayer rejects it)
  ├─ fetches the real https URL
  └─ rewrites URIs: sub-playlists stay intercepted, segments/init/keys → absolute https
     (AVFoundation can't serve HLS segments through a resource loader)
  ↓
AVPlayer plays fMP4 HLS
```

## Build & sideload

1. **Create a GitHub repo** and push all files.
2. **Edit `CinejoyNative/Info.plist`** — set `TMDB_API_KEY` to your free key from
   https://www.themoviedb.org/settings/api
3. **Push to `main`** — GitHub Actions builds an unsigned `.ipa` (Artifacts tab).
4. **Sideload via ATVLoadly** — upload the `.ipa`, sign with your Apple ID, install.

> **ATVLoadly limits:** tvOS ≤ 16.5 only, free Apple ID gives 7-day expiry and 3 active apps.
> Re-sideload weekly, or use a paid Apple Developer account ($99/yr) for 1-year provisioning.

## What's confirmed working

| Layer | Status |
|---|---|
| Movie pipeline (`/Nebula/movie`) | ✅ Verified end-to-end |
| TV pipeline (`/Nebula/series` + season/episode) | ✅ Verified end-to-end |
| HLS content-type fix (`image/jpeg` spoofing) | Handled by `HLSResourceLoader` (playlists only; segments load directly) |
| `api.wing.st/info` for detail view | ✅ |
| TMDB search + fallback IMDB via `external_ids` | ✅ |

## Known caveats

- **Free Apple ID = 7-day re-sideload.** Unavoidable without paid developer account.
- **Site can rotate `crush.wasm`** — build workflow re-downloads it each push, so a rebuild + re-sideload survives any rotation.
- **`/g` protocol can change** — a full protocol change would need re-reverse-engineering.
- **TV season count is hardcoded to 30** — extend in `MovieDetailView` if needed.
