import SwiftUI

struct SearchView: View {
    @StateObject private var vm = SearchViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                if vm.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(80)
                } else if let error = vm.errorMessage {
                    Text(error).foregroundStyle(.red).padding(60)
                } else if vm.results.isEmpty && !vm.searchText.isEmpty {
                    Text("No results for \"\(vm.searchText)\"")
                        .foregroundStyle(.secondary).padding(60)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: UI.s(230)), spacing: UI.s(40))], spacing: UI.s(50)) {
                        ForEach(vm.results) { PosterCard(media: $0) }
                    }
                    .padding(UI.s(40))
                }
            }
            .searchable(text: $vm.searchText, prompt: "Movies and TV shows")
            .onChange(of: vm.searchText) { _ in          // single-value signature for tvOS 16
                Task { await vm.performSearch() }
            }
            .mediaDestinations()
        }
    }
}
