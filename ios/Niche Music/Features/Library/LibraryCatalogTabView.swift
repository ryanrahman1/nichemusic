//
//  LibraryCatalogTabView.swift
//  Niche Music
//

import SwiftUI

struct LibraryCatalogTabView: View {
    let source: LibrarySource
    @Binding var browseRoute: LibraryBrowseRoute?
    @Binding var searchRoute: LibrarySearchRoute?

    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var profileStore: ProfileStore

    private var likedSongs: [ProfileMusicSong] {
        filterSongs(profileStore.likedSongs, source: source)
    }

    private var savedSongs: [ProfileMusicSong] {
        filterSongs(profileStore.savedSongs, source: source)
    }

    private var trendingSongs: [CatalogTrack] {
        filterTracks(libraryStore.trendingSongs, source: source)
    }

    private var trendingAlbums: [CatalogAlbum] {
        filterAlbums(libraryStore.trendingAlbums, source: source)
    }

    private var trendingArtists: [CatalogArtist] {
        filterArtists(libraryStore.trendingArtists, source: source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Button {
                searchRoute = LibrarySearchRoute(source: source)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.42))

                    Text("Search \(source.displayName)")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.42))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)

            if profileStore.isLoadingMusic && savedSongs.isEmpty && likedSongs.isEmpty {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            } else {
                songRail(
                    title: "Saved Tracks",
                    songs: savedSongs,
                    emptyMessage: "No saved \(source.displayName) tracks yet."
                )

                songRail(
                    title: "Liked Tracks",
                    songs: likedSongs,
                    emptyMessage: "No liked \(source.displayName) tracks yet."
                )
            }

            if libraryStore.isLoadingTrending && trendingSongs.isEmpty && trendingAlbums.isEmpty {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            } else {
                trendingRail(
                    title: "Trending Songs",
                    isEmpty: trendingSongs.isEmpty,
                    seeAll: {
                        browseRoute = LibraryBrowseRoute(
                            source: source,
                            kind: .trending,
                            filter: .songs
                        )
                    }
                ) {
                    ForEach(trendingSongs.prefix(8)) { track in
                        LibraryTrendingSongCard(track: track)
                    }
                }

                trendingRail(
                    title: "Trending Albums",
                    isEmpty: trendingAlbums.isEmpty,
                    seeAll: {
                        browseRoute = LibraryBrowseRoute(
                            source: source,
                            kind: .trending,
                            filter: .albums
                        )
                    }
                ) {
                    ForEach(trendingAlbums.prefix(8)) { album in
                        LibraryTrendingAlbumCard(album: album)
                    }
                }

                trendingRail(
                    title: "Trending Artists",
                    isEmpty: trendingArtists.isEmpty,
                    seeAll: {
                        browseRoute = LibraryBrowseRoute(
                            source: source,
                            kind: .trending,
                            filter: .artists
                        )
                    }
                ) {
                    ForEach(trendingArtists.prefix(8)) { artist in
                        LibraryTrendingArtistCard(artist: artist)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func songRail(
        title: String,
        songs: [ProfileMusicSong],
        emptyMessage: String
    ) -> some View {
        if songs.isEmpty {
            LibraryHorizontalRail(title: title, emptyMessage: emptyMessage) {
                EmptyView()
            }
        } else {
            LibraryHorizontalRail(title: title) {
                ForEach(Array(songs.prefix(12)), id: \.id) { song in
                    LibrarySongCard(song: song)
                }
            }
        }
    }

    @ViewBuilder
    private func trendingRail<Content: View>(
        title: String,
        isEmpty: Bool,
        seeAll: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        if isEmpty {
            EmptyView()
        } else {
            LibraryHorizontalRail(title: title, actionTitle: "See all", action: seeAll, content: content)
        }
    }
}
