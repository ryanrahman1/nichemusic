//
//  LibraryStore.swift
//  Niche Music
//

import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var trendingSongs: [CatalogTrack] = []
    @Published private(set) var trendingAlbums: [CatalogAlbum] = []
    @Published private(set) var trendingArtists: [CatalogArtist] = []
    @Published private(set) var isLoadingTrending = false
    @Published private(set) var trendingError: String?

    @Published private(set) var isSearching = false
    @Published private(set) var searchError: String?

    private let api = APIClient.shared
    private let previewLimit = 8
    private let pageSize = 20

    private var trendingLoadedAt: Date?
    private let trendingTtl: TimeInterval = 180

    private var songsNextCursor: String?
    private var albumsNextCursor: String?
    private var artistsNextCursor: String?
    private var songsHasMore = false
    private var albumsHasMore = false
    private var artistsHasMore = false

    func loadTrendingPreview(force: Bool = false) async {
        if isLoadingTrending { return }
        if !force,
           let trendingLoadedAt,
           Date().timeIntervalSince(trendingLoadedAt) < trendingTtl,
           !trendingSongs.isEmpty {
            return
        }

        isLoadingTrending = true
        trendingError = nil

        do {
            async let songs = fetchTrendingSongs(cursor: nil, limit: previewLimit)
            async let albums = fetchTrendingAlbums(cursor: nil, limit: previewLimit)
            async let artists = fetchTrendingArtists(cursor: nil, limit: previewLimit)
            let (songPage, albumPage, artistPage) = try await (songs, albums, artists)

            trendingSongs = songPage.items.map { $0.asCatalogTrack() }
            trendingAlbums = albumPage.items.map { $0.asCatalogAlbum() }
            trendingArtists = artistPage.items.map { $0.asCatalogArtist() }
            songsNextCursor = songPage.nextCursor
            albumsNextCursor = albumPage.nextCursor
            artistsNextCursor = artistPage.nextCursor
            songsHasMore = songPage.hasMore
            albumsHasMore = albumPage.hasMore
            artistsHasMore = artistPage.hasMore
            trendingLoadedAt = Date()
        } catch {
            trendingError = error.localizedDescription
        }

        isLoadingTrending = false
    }

    func loadTrendingPage(
        filter: LibraryContentFilter,
        cursor: String?
    ) async throws -> TrendingPage<AnyCatalogItem> {
        switch filter {
        case .songs:
            let page = try await fetchTrendingSongs(cursor: cursor, limit: pageSize)
            return TrendingPage(
                items: page.items.map { AnyCatalogItem.song($0.asCatalogTrack()) },
                nextCursor: page.nextCursor,
                hasMore: page.hasMore
            )
        case .albums:
            let page = try await fetchTrendingAlbums(cursor: cursor, limit: pageSize)
            return TrendingPage(
                items: page.items.map { AnyCatalogItem.album($0.asCatalogAlbum()) },
                nextCursor: page.nextCursor,
                hasMore: page.hasMore
            )
        case .artists:
            let page = try await fetchTrendingArtists(cursor: cursor, limit: pageSize)
            return TrendingPage(
                items: page.items.map { AnyCatalogItem.artist($0.asCatalogArtist()) },
                nextCursor: page.nextCursor,
                hasMore: page.hasMore
            )
        }
    }

    func hasMoreTrending(for filter: LibraryContentFilter) -> Bool {
        switch filter {
        case .songs: return songsHasMore
        case .albums: return albumsHasMore
        case .artists: return artistsHasMore
        }
    }

    func searchAppleMusic(
        query: String,
        filter: LibraryContentFilter
    ) async -> [AnyCatalogItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        isSearching = true
        searchError = nil
        defer { isSearching = false }

        let types: String
        switch filter {
        case .songs: types = "songs"
        case .albums: types = "albums"
        case .artists: types = "artists"
        }

        do {
            let response: AppleMusicSearchResponse = try await api.request(
                Endpoints.appleMusicSearch,
                method: .get,
                query: ["q": trimmed, "types": types]
            )

            switch filter {
            case .songs:
                return (response.data.results?.songs?.data ?? []).map { song in
                    AnyCatalogItem.searchSong(song)
                }
            case .albums:
                return (response.data.results?.albums?.data ?? []).map { album in
                    AnyCatalogItem.searchAlbum(album)
                }
            case .artists:
                return (response.data.results?.artists?.data ?? []).map { artist in
                    AnyCatalogItem.searchArtist(artist)
                }
            }
        } catch {
            searchError = error.localizedDescription
            return []
        }
    }

    func searchCatalog(
        query: String,
        filter: LibraryContentFilter,
        source: LibrarySource,
        likedSongs: [ProfileMusicSong],
        savedSongs: [ProfileMusicSong],
        followingArtists: [ProfileFollowingArtist]
    ) -> [AnyCatalogItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }

        switch filter {
        case .songs:
            let pool = (likedSongs + savedSongs + trendingSongs.compactMap(\.asProfileSong))
                .filter { source.matches($0.source) }
            var seen = Set<String>()
            return pool.filter { song in
                guard !seen.contains(song.id) else { return false }
                seen.insert(song.id)
                return song.name.lowercased().contains(trimmed)
            }.map { AnyCatalogItem.profileSong($0) }

        case .albums:
            return trendingAlbums
                .filter { source.matches($0.source) && $0.name.lowercased().contains(trimmed) }
                .map { AnyCatalogItem.album($0) }

        case .artists:
            let pool = followingArtists.filter { source.matches($0.source) }
                + trendingArtists
                    .filter { source.matches($0.source) }
                    .map {
                        ProfileFollowingArtist(
                            id: $0.id,
                            name: $0.name,
                            source: $0.source,
                            sourceId: $0.sourceId,
                            ownerId: $0.ownerId,
                            imageUrl: $0.imageUrl
                        )
                    }
            var seen = Set<String>()
            return pool.filter { artist in
                guard !seen.contains(artist.id) else { return false }
                seen.insert(artist.id)
                return artist.name.lowercased().contains(trimmed)
            }.map { AnyCatalogItem.followingArtist($0) }
        }
    }

    private func fetchTrendingSongs(cursor: String?, limit: Int) async throws -> TrendingPage<TrendingTrack> {
        let response: (result: TrendingSongsResponse, metadata: APIMetadata?) =
            try await api.requestWithMetadata(
                Endpoints.musicLibrarySongs,
                method: .get,
                query: buildTrendingQuery(cursor: cursor, limit: limit)
            )
        let pagination = response.metadata?.pagination
        return TrendingPage(
            items: response.result.songs,
            nextCursor: pagination?.nextCursor,
            hasMore: pagination?.hasMore ?? false
        )
    }

    private func fetchTrendingAlbums(cursor: String?, limit: Int) async throws -> TrendingPage<TrendingAlbum> {
        let response: (result: TrendingAlbumsResponse, metadata: APIMetadata?) =
            try await api.requestWithMetadata(
                Endpoints.musicLibraryAlbums,
                method: .get,
                query: buildTrendingQuery(cursor: cursor, limit: limit)
            )
        let pagination = response.metadata?.pagination
        return TrendingPage(
            items: response.result.albums,
            nextCursor: pagination?.nextCursor,
            hasMore: pagination?.hasMore ?? false
        )
    }

    private func fetchTrendingArtists(cursor: String?, limit: Int) async throws -> TrendingPage<TrendingArtist> {
        let response: (result: TrendingArtistsResponse, metadata: APIMetadata?) =
            try await api.requestWithMetadata(
                Endpoints.musicLibraryArtists,
                method: .get,
                query: buildTrendingQuery(cursor: cursor, limit: limit)
            )
        let pagination = response.metadata?.pagination
        return TrendingPage(
            items: response.result.artists,
            nextCursor: pagination?.nextCursor,
            hasMore: pagination?.hasMore ?? false
        )
    }

    private func buildTrendingQuery(cursor: String?, limit: Int) -> [String: String?] {
        var query: [String: String?] = [
            "limit": String(limit),
            "windowDays": "14",
            "cursorScore": nil,
            "cursorCreatedAt": nil,
            "cursorId": nil,
        ]

        if let cursor, let decoded = TrendingLibraryCursor(rawValue: cursor) {
            if let cursorScore = decoded.cursorScore {
                query["cursorScore"] = String(cursorScore)
            }
            query["cursorCreatedAt"] = decoded.cursorCreatedAt
            query["cursorId"] = decoded.cursorId
        }

        return query
    }
}

enum AnyCatalogItem: Identifiable {
    case song(CatalogTrack)
    case album(CatalogAlbum)
    case artist(CatalogArtist)
    case profileSong(ProfileMusicSong)
    case followingArtist(ProfileFollowingArtist)
    case searchSong(AppleMusicSearchSong)
    case searchAlbum(AppleMusicSearchAlbum)
    case searchArtist(AppleMusicSearchArtist)

    var id: String {
        switch self {
        case .song(let item): return "song-\(item.id)"
        case .album(let item): return "album-\(item.id)"
        case .artist(let item): return "artist-\(item.id)"
        case .profileSong(let item): return "profile-song-\(item.id)"
        case .followingArtist(let item): return "following-artist-\(item.id)"
        case .searchSong(let item): return "search-song-\(item.id)"
        case .searchAlbum(let item): return "search-album-\(item.id)"
        case .searchArtist(let item): return "search-artist-\(item.id)"
        }
    }
}

private extension CatalogTrack {
    var asProfileSong: ProfileMusicSong? {
        ProfileMusicSong(
            id: id,
            name: name,
            source: source,
            albumId: albumId,
            artistId: artistId ?? "",
            sourceId: sourceId,
            artworkUrl: artworkUrl,
            artistName: artistName,
            viewer: viewer.map { ProfileMusicSongViewer(isLiked: $0.isLiked, isSaved: $0.isSaved) }
        )
    }
}
