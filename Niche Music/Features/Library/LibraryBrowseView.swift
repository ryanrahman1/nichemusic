//
//  LibraryBrowseView.swift
//  Niche Music
//

import SwiftUI

struct LibraryBrowseView: View {
    let route: LibraryBrowseRoute

    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var profileStore: ProfileStore

    @State private var selectedFilter: LibraryContentFilter
    @State private var items: [AnyCatalogItem] = []
    @State private var nextCursor: String?
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?

    init(route: LibraryBrowseRoute) {
        self.route = route
        _selectedFilter = State(initialValue: route.filter)
    }

    private var title: String {
        "\(route.source.displayName) \(route.kind.rawValue)"
    }

    var body: some View {
        VStack(spacing: 0) {
            LibraryFilterChips(selectedFilter: $selectedFilter)
                .padding(.top, 8)
                .padding(.bottom, 12)

            if isLoading && items.isEmpty {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, items.isEmpty {
                MusicDetailErrorState(message: errorMessage) {
                    Task { await reload() }
                }
            } else if items.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            LibraryCatalogItemRow(item: item)
                                .onAppear {
                                    loadMoreIfNeeded(currentItem: item)
                                }
                        }

                        if isLoadingMore {
                            ProgressView()
                                .tint(.white)
                                .padding(.vertical, 16)
                        }
                    }
                    .padding(.bottom, 120)
                }
            }
        }
        .background(Theme.backgroundColor.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Theme.backgroundColor, for: .navigationBar)
        .task(id: selectedFilter) {
            await reload()
        }
    }

    private var emptyMessage: String {
        switch route.kind {
        case .saved:
            return "No saved \(selectedFilter.rawValue.lowercased()) in your \(route.source.displayName) library yet."
        case .liked:
            return "No liked \(selectedFilter.rawValue.lowercased()) in your \(route.source.displayName) library yet."
        case .trending:
            return "No trending \(selectedFilter.rawValue.lowercased()) right now."
        }
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        nextCursor = nil
        hasMore = false
        items = []

        await loadPage(cursor: nil, replace: true)
        isLoading = false
    }

    private func loadMoreIfNeeded(currentItem: AnyCatalogItem) {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        guard items.last?.id == currentItem.id else { return }
        Task { await loadPage(cursor: nextCursor, replace: false) }
    }

    private func loadPage(cursor: String?, replace: Bool) async {
        if cursor != nil {
            isLoadingMore = true
        }

        defer { isLoadingMore = false }

        do {
            let pageItems: [AnyCatalogItem]
            let pageNextCursor: String?
            let pageHasMore: Bool

            switch route.kind {
            case .trending:
                let page = try await libraryStore.loadTrendingPage(
                    filter: selectedFilter,
                    cursor: cursor
                )
                pageItems = filterTrendingItems(page.items)
                pageNextCursor = page.nextCursor
                pageHasMore = page.hasMore

            case .saved, .liked:
                let collection = try await loadCollectionPage(cursor: cursor)
                pageItems = collection.items
                pageNextCursor = collection.nextCursor
                pageHasMore = collection.hasMore
            }

            if replace {
                items = pageItems
            } else {
                let existing = Set(items.map(\.id))
                items.append(contentsOf: pageItems.filter { !existing.contains($0.id) })
            }

            nextCursor = pageNextCursor
            hasMore = pageHasMore
        } catch {
            if replace {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func filterTrendingItems(_ items: [AnyCatalogItem]) -> [AnyCatalogItem] {
        items.filter { item in
            switch item {
            case .song(let track):
                return route.source.matches(track.source)
            case .album(let album):
                return route.source.matches(album.source)
            case .artist(let artist):
                return route.source.matches(artist.source)
            default:
                return false
            }
        }
    }

    private func loadCollectionPage(cursor: String?) async throws -> (items: [AnyCatalogItem], nextCursor: String?, hasMore: Bool) {
        switch selectedFilter {
        case .songs:
            let page = try await fetchSongCollection(cursor: cursor)
            let filtered = filterSongs(page.songs, source: route.source)
            return (
                filtered.map { AnyCatalogItem.profileSong($0) },
                page.nextCursor,
                page.hasMore
            )
        case .albums:
            return ([], nil, false)
        case .artists:
            if route.kind == .liked {
                let page = try await fetchFollowingPage(cursor: cursor)
                let filtered = filterFollowingArtists(page.artists, source: route.source)
                return (
                    filtered.map { AnyCatalogItem.followingArtist($0) },
                    page.nextCursor,
                    page.hasMore
                )
            }
            let page = try await libraryStore.loadTrendingPage(filter: .artists, cursor: cursor)
            let filtered = filterTrendingItems(page.items)
            return (filtered, page.nextCursor, page.hasMore)
        }
    }

    private func fetchSongCollection(cursor: String?) async throws -> ProfileMusicSongPage {
        let endpoint = route.kind == .saved ? Endpoints.musicMeSaved : Endpoints.musicMeLiked
        let response: (result: ProfileMusicSongResponse, metadata: APIMetadata?) =
            try await APIClient.shared.requestWithMetadata(
                endpoint,
                method: .get,
                query: buildSongCursorQuery(cursor: cursor)
            )
        let pagination = response.metadata?.pagination
        return ProfileMusicSongPage(
            requestCursor: cursor,
            songs: response.result.songs,
            nextCursor: pagination?.nextCursor,
            hasMore: pagination?.hasMore ?? false,
            limit: pagination?.limit ?? 20,
            fetchedAt: Date()
        )
    }

    private func fetchFollowingPage(cursor: String?) async throws -> ProfileFollowingArtistPage {
        let response: (result: ProfileFollowingArtistResponse, metadata: APIMetadata?) =
            try await APIClient.shared.requestWithMetadata(
                Endpoints.musicMeFollowing,
                method: .get,
                query: buildSongCursorQuery(cursor: cursor)
            )
        let pagination = response.metadata?.pagination
        return ProfileFollowingArtistPage(
            requestCursor: cursor,
            artists: response.result.artists,
            nextCursor: pagination?.nextCursor,
            hasMore: pagination?.hasMore ?? false,
            limit: pagination?.limit ?? 20,
            fetchedAt: Date()
        )
    }

    private func buildSongCursorQuery(cursor: String?) -> [String: String?] {
        var query: [String: String?] = [
            "type": "songs",
            "limit": "20",
            "cursorCreatedAt": nil,
        ]

        if let cursor,
           let data = cursor.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data),
           let createdAt = decoded["cursorCreatedAt"] {
            query["cursorCreatedAt"] = createdAt
        }

        return query
    }
}
