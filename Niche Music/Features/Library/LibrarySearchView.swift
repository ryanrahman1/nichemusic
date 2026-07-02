//
//  LibrarySearchView.swift
//  Niche Music
//

import SwiftUI

struct LibrarySearchView: View {
    let source: LibrarySource

    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var profileStore: ProfileStore

    @State private var query = ""
    @State private var selectedFilter: LibraryContentFilter = .songs
    @State private var results: [AnyCatalogItem] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            LibrarySearchField(text: $query, placeholder: "Search songs, albums, artists")
                .padding(.top, 8)
                .padding(.bottom, 12)

            LibraryFilterChips(selectedFilter: $selectedFilter)
                .padding(.bottom, 12)

            if libraryStore.isSearching && results.isEmpty && !query.isEmpty {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { item in
                            LibraryCatalogItemRow(item: item)
                        }
                    }
                    .padding(.bottom, 120)
                }
            }
        }
        .background(Theme.backgroundColor.ignoresSafeArea())
        .navigationTitle("\(source.displayName) Search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Theme.backgroundColor, for: .navigationBar)
        .onChange(of: query) { _, _ in
            scheduleSearch()
        }
        .onChange(of: selectedFilter) { _, _ in
            scheduleSearch()
        }
        .task {
            await libraryStore.loadTrendingPreview()
            await profileStore.loadMyMusic()
        }
    }

    private var emptyMessage: String {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Search your \(source.displayName) library by song, album, or artist."
        }
        if let searchError = libraryStore.searchError {
            return searchError
        }
        return "No results for \"\(query)\"."
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await performSearch()
        }
    }

    private func performSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }

        switch source {
        case .appleMusic:
            let found = await libraryStore.searchAppleMusic(query: trimmed, filter: selectedFilter)
            results = found
        case .niche, .yourLibrary:
            results = libraryStore.searchCatalog(
                query: trimmed,
                filter: selectedFilter,
                source: source,
                likedSongs: profileStore.likedSongs,
                savedSongs: profileStore.savedSongs,
                followingArtists: profileStore.followingArtistProfiles
            )
        }
    }
}
