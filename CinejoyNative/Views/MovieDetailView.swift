import SwiftUI

struct MovieDetailView: View {
    let movie: MovieInfo

    @StateObject private var playback = PlaybackViewModel()
    @State private var showPlayer = false
    @State private var cinejoyInfo: CinejoyAPI.CinejoyInfo?
    @State private var imdbID = ""
    @State private var season = 1
    @State private var episode = 1

    private var isTV: Bool { movie.mediaType == "tv" }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 50) {
                posterView
                detailsView
            }
            .padding(60)
        }
        .navigationTitle(movie.displayTitle)
        .task { await loadDetails() }
        .fullScreenCover(isPresented: $showPlayer) {
            if let player = playback.player {
                PlayerView(player: player, errorMessage: playback.errorMessage)
                    .ignoresSafeArea()
            }
        }
        .alert("Playback Error",
               isPresented: .init(
                   get: { playback.errorMessage != nil },
                   set: { if !$0 { playback.errorMessage = nil } }
               )
        ) {
            Button("OK") { playback.errorMessage = nil }
        } message: {
            Text(playback.errorMessage ?? "")
        }
    }

    private var posterView: some View {
        AsyncImage(url: movie.posterURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(2/3, contentMode: .fit)
            default:
                Rectangle().fill(.gray.opacity(0.3)).overlay(ProgressView())
            }
        }
        .frame(width: 400, height: 600)
        .clipShape(RoundedRectangle(cornerRadius: 15))
    }

    private var detailsView: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(movie.title ?? movie.name ?? "Unknown")
                .font(.largeTitle).bold()

            if let overview = cinejoyInfo?.overview ?? movie.overview, !overview.isEmpty {
                Text(overview).font(.body).lineLimit(12)
            }

            if isTV {
                HStack(spacing: 24) {
                    Picker("Season", selection: $season) {
                        ForEach(1...30, id: \.self) { Text("Season \($0)").tag($0) }
                    }
                    .frame(width: 260)          // no .pickerStyle(.menu) — tvOS 16 default is segmented

                    Picker("Episode", selection: $episode) {
                        ForEach(1...60, id: \.self) { Text("Episode \($0)").tag($0) }
                    }
                    .frame(width: 260)
                }
            }

            Button {
                Task { await play() }
            } label: {
                HStack {
                    if playback.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(playback.isLoading ? "Preparing stream…" : "Play")
                }
                .font(.headline)
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .disabled(playback.isLoading)
        }
        .frame(maxWidth: 700, alignment: .leading)
    }

    private func loadDetails() async {
        do {
            let info = try await CinejoyAPI.shared.fetchInfo(
                tmdbID: movie.tmdbID,
                mediaType: movie.mediaType ?? "movie"
            )
            cinejoyInfo = info
            imdbID = info.imdb ?? ""
            if imdbID.isEmpty {
                imdbID = try await CinejoyAPI.shared.fetchIMDBID(
                    tmdbID: movie.tmdbID,
                    mediaType: movie.mediaType ?? "movie"
                )
            }
        } catch {
            imdbID = (try? await CinejoyAPI.shared.fetchIMDBID(
                tmdbID: movie.tmdbID,
                mediaType: movie.mediaType ?? "movie"
            )) ?? ""
        }
    }

    private func play() async {
        do {
            let imdb = imdbID.isEmpty
                ? try await CinejoyAPI.shared.fetchIMDBID(
                    tmdbID: movie.tmdbID,
                    mediaType: movie.mediaType ?? "movie"
                )
                : imdbID
            let year = String((cinejoyInfo?.year
                               ?? movie.releaseDate
                               ?? movie.firstAirDate
                               ?? "").prefix(4))
            let title = cinejoyInfo?.title ?? movie.title ?? movie.name ?? ""

            let url: URL
            if isTV {
                url = try await CinejoyAPI.shared.resolveTVStreamURL(
                    tmdbID: movie.tmdbID, imdbID: imdb, year: year, title: title,
                    season: season, episode: episode
                )
            } else {
                url = try await CinejoyAPI.shared.resolveMovieStreamURL(
                    tmdbID: movie.tmdbID, imdbID: imdb, year: year, title: title
                )
            }

            playback.startPlayback(url: url)
            showPlayer = true
        } catch {
            playback.errorMessage = error.localizedDescription
        }
    }
}
