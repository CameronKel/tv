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

## App

- **Navigation**: a menu down the right edge (Home, Movies, TV Shows, Search). Swipe right to
  reach it; it widens to show names, and moving through it switches section.

- **Home**: featured title, Continue Watching, Recently Watched, My List,
  "Because you watched …", then trending and popular rows.
- **Movies / TV Shows**: featured title, trending/popular/top-rated rows and genre rows (TMDB).
- **Detail**: backdrop, info, Play/Resume, My List, More Like This. Shows get a
  season picker and episode cards with progress; Play continues where you left off
  or starts the next episode.
- Watch progress and My List are stored on the device (`WatchHistory`, UserDefaults).
  Long-press a Continue Watching card to open details or remove it.

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
| Sources | `/<source>/movie` and `/<source>/series`, tried in order: `Nebula` (1080p, smoothest), `secret` (titles Nebula lacks, up to 4K HDR), then `Lisbon`, `Athens`, `Solara`. `api.wing.st/servers` lists them. If a stream fails or stalls (20 s) before it starts, the next source is tried, and that source goes last for the rest of the launch |
| Movie and TV pipelines | ✅ Verified end-to-end on `secret` and `Nebula` |
| HLS content-type fix (`image/jpeg` spoofing) | Handled by `HLSResourceLoader` (playlists only; segments load directly) |
| IMDB id for the resolver | TMDB `external_ids` (fetched with the detail page, cached per launch). `api.wing.st/info` returns 502, so it is no longer used |
| TMDB search + fallback IMDB via `external_ids` | ✅ |

## Known caveats

- **Free Apple ID = 7-day re-sideload.** Unavoidable without paid developer account.
- **Site can rotate `crush.wasm`** — build workflow re-downloads it each push, so a rebuild + re-sideload survives any rotation.
- **`/g` protocol can change** — a full protocol change would need re-reverse-engineering.
