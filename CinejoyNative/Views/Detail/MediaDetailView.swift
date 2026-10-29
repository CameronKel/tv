import SwiftUI

/// A movie or show: backdrop, info, Play/Resume, My List, episodes for shows,
/// and "More Like This".
struct MediaDetailView: View {
    let media: MovieInfo

    @EnvironmentObject private var playback: PlaybackViewModel
    @EnvironmentObject private var history: WatchHistory
    @State private var details: MediaDetails?
    @State private var selectedSeason: Int?
    @State private var episodes: [Episode] = []
    @State private var loadingEpisodes = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            backdrop
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    header
                    if media.isTV, let seasons = details?.playableSeasons, !seasons.isEmpty {
                        EpisodesSection(media: media, seasons: seasons, selectedSeason: $selectedSeason,
                                        episodes: episodes, isLoading: loadingEpisodes)
                    }
                    if let recommended = details?.recommended(as: media.mediaType), !recommended.isEmpty {
                        MediaRow(title: "More Like This", items: recommended)
                    }
                }
                .padding(.vertical, 60)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task(id: media.id) { await loadDetails() }
        .task(id: selectedSeason) { await loadEpisodes() }
    }

    // MARK: - Pieces

    private var backdrop: some View {
        RemoteImage(url: media.backdropURL)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay(
                LinearGradient(colors: [.black.opacity(0.95), .black.opacity(0.6), .black.opacity(0.2)],
                               startPoint: .leading, endPoint: .trailing)
            )
            .overlay(
                LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom)
            )
            .ignoresSafeArea()
    }

    private var header: some View {
        let target = playTarget
        let inList = history.isInMyList(media)
        return VStack(alignment: .leading, spacing: 20) {
            Text(media.displayName)
                .font(.system(size: 76, weight: .bold))
                .lineLimit(2)
            Text(metadata)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let tagline = details?.tagline, !tagline.isEmpty {
                Text(tagline).font(.callout).italic()
            }
            if let overview = media.overview, !overview.isEmpty {
                Text(overview)
                    .font(.callout)
                    .lineLimit(5)
                    .frame(maxWidth: 1050, alignment: .leading)
            }

            HStack(spacing: 30) {
                Button {
                    playback.play(media, target: target)
                } label: {
                    Label(target.label, systemImage: "play.fill")
                }
                Button {
                    history.toggleMyList(media)
                } label: {
                    Label(inList ? "In My List" : "My List", systemImage: inList ? "checkmark" : "plus")
                }
            }
            .padding(.top, 16)

            if let entry = history.entry(for: media), !entry.isFinished, !entry.upNext, target.resumeAt > 0 {
                HStack(spacing: 20) {
                    ProgressBar(value: entry.progress).frame(width: 300)
                    Text("\(entry.minutesLeft) min left").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 120)
        .focusSection()
    }

    private var playTarget: PlayTarget {
        var target = history.playTarget(for: media, firstSeason: firstSeason)
        if target.episodeTitle == nil, target.season == selectedSeason,
           let episode = episodes.first(where: { $0.episodeNumber == target.episode }) {
            target.episodeTitle = episode.name
        }
        return target
    }

    private var firstSeason: Int {
        details?.playableSeasons.first?.seasonNumber ?? 1
    }

    private var metadata: String {
        var parts: [String] = []
        if let year = media.year { parts.append(year) }
        if media.isTV {
            if let count = details?.numberOfSeasons {
                parts.append(count == 1 ? "1 Season" : "\(count) Seasons")
            }
        } else if let runtime = details?.runtime, runtime > 0 {
            parts.append(runtime >= 60 ? "\(runtime / 60)h \(runtime % 60)m" : "\(runtime)m")
        }
        if let rating = media.voteAverage, rating > 0 {
            parts.append(String(format: "★ %.1f", rating))
        }
        if let genres = details?.genres, !genres.isEmpty {
            parts.append(genres.prefix(3).map(\.name).joined(separator: ", "))
        }
        return parts.joined(separator: "   ·   ")
    }

    // MARK: - Loading

    private func loadDetails() async {
        details = try? await CinejoyAPI.shared.details(for: media)
        if media.isTV, selectedSeason == nil {
            selectedSeason = history.playTarget(for: media, firstSeason: firstSeason).season ?? firstSeason
        }
    }

    private func loadEpisodes() async {
        guard media.isTV, let season = selectedSeason else { return }
        loadingEpisodes = true
        defer { loadingEpisodes = false }
        episodes = (try? await CinejoyAPI.shared.season(showID: media.tmdbID, number: season).episodes) ?? []
    }
}
