import SwiftUI

/// Season picker plus a row of episode cards for the selected season.
struct EpisodesSection: View {
    let media: MovieInfo
    let seasons: [SeasonSummary]
    @Binding var selectedSeason: Int?
    let episodes: [Episode]
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RowHeader(title: "Episodes")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(seasons) { season in
                        SeasonButton(
                            title: season.name ?? "Season \(season.seasonNumber)",
                            isSelected: season.seasonNumber == selectedSeason
                        ) {
                            selectedSeason = season.seasonNumber
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .focusSection()

            if isLoading && episodes.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(60)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 40) {
                        ForEach(episodes) { episode in
                            EpisodeCard(media: media, season: selectedSeason ?? 1, episode: episode)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 36)
                }
                .focusSection()
            }
        }
    }
}

private struct SeasonButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        if isSelected {
            Button(action: action) { label }.buttonStyle(.borderedProminent)
        } else {
            Button(action: action) { label }
        }
    }

    private var label: some View {
        Text(title).fontWeight(isSelected ? .bold : .regular)
    }
}

private struct EpisodeCard: View {
    let media: MovieInfo
    let season: Int
    let episode: Episode

    @EnvironmentObject private var playback: PlaybackViewModel
    @EnvironmentObject private var history: WatchHistory

    var body: some View {
        let mark = history.mark(showID: media.tmdbID, season: season, episode: episode.episodeNumber)
        let progress = mark?.progress ?? 0
        let watched = progress >= WatchEntry.finishedThreshold

        VStack(alignment: .leading, spacing: 10) {
            Button {
                let resume = (progress > 0 && !watched) ? (mark?.position ?? 0) : 0
                playback.play(media, season: season, episode: episode.episodeNumber,
                              episodeTitle: episode.name, resumeAt: resume)
            } label: {
                RemoteImage(url: episode.stillURL ?? media.backdropURL)
                    .frame(width: 440, height: 248)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        if progress > 0 && !watched {
                            ProgressBar(value: progress).padding(16)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if watched {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .padding(14)
                        }
                    }
            }
            .buttonStyle(.card)

            Text("\(episode.episodeNumber). \(episode.name ?? "Episode \(episode.episodeNumber)")")
                .font(.headline)
                .lineLimit(1)
            if let details = detailsLine {
                Text(details).font(.caption2).foregroundStyle(.secondary)
            }
            if let overview = episode.overview, !overview.isEmpty {
                Text(overview)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .frame(width: 440, alignment: .leading)
    }

    private var detailsLine: String? {
        var parts: [String] = []
        if let runtime = episode.runtime, runtime > 0 { parts.append("\(runtime) min") }
        if let date = episode.airDate, !date.isEmpty { parts.append(date) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
