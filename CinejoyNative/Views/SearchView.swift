import SwiftUI

struct SearchView: View {
    @StateObject private var vm = SearchViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                if vm.isLoading {
                    ProgressView("Searching…").padding(60)
                } else if let error = vm.errorMessage {
                    Text(error).foregroundStyle(.red).padding(60)
                } else if vm.results.isEmpty && !vm.searchText.isEmpty {
                    Text("No results for \"\(vm.searchText)\"")
                        .foregroundStyle(.secondary).padding(60)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260))], spacing: 40) {
                        ForEach(vm.results) { movie in
                            NavigationLink(value: movie) {
                                MoviePosterCard(movie: movie)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(50)
                }
            }
            .searchable(text: $vm.searchText, prompt: "Search movies and shows")
            .onChange(of: vm.searchText) { _, _ in
                Task { await vm.performSearch() }
            }
            .navigationDestination(for: MovieInfo.self) { movie in
                MovieDetailView(movie: movie)
            }
            .navigationTitle("Cinejoy")
        }
    }
}

struct MoviePosterCard: View {
    let movie: MovieInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AsyncImage(url: movie.posterURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(2/3, contentMode: .fill)
                case .failure:
                    Rectangle().fill(.gray.opacity(0.3))
                        .overlay(Image(systemName: "film").font(.largeTitle))
                default:
                    Rectangle().fill(.gray.opacity(0.2))
                        .overlay(ProgressView())
                }
            }
            .frame(width: 260, height: 390)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(movie.displayTitle)
                .font(.headline)
                .lineLimit(2)
                .frame(width: 260, alignment: .leading)
        }
    }
}
