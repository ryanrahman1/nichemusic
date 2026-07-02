//
//  ProfileUserMusicTabView.swift
//  Niche Music
//

import SwiftUI

struct ProfileUserMusicTabView: View {
    enum Scope: Equatable {
        case ownProfile
        case user(username: String)
    }

    let scope: Scope

    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var playlistStore: PlaylistStore

    private let railItemLimit = 12

    private var isOwnProfile: Bool {
        if case .ownProfile = scope { return true }
        return false
    }

    private var username: String? {
        if case .user(let username) = scope { return username }
        return nil
    }

    private var likedSongs: [ProfileMusicSong] {
        switch scope {
        case .ownProfile:
            return profileStore.likedSongs
        case .user(let username):
            return profileStore.otherProfile(for: username)?.likedSongs ?? []
        }
    }

    private var savedSongs: [ProfileMusicSong] {
        profileStore.savedSongs
    }

    private var followingArtists: [ProfileFollowingArtist] {
        switch scope {
        case .ownProfile:
            return profileStore.followingArtistProfiles
        case .user(let username):
            return profileStore.otherProfile(for: username)?.followingArtists ?? []
        }
    }

    private var playlists: [PlaylistSummary] {
        switch scope {
        case .ownProfile:
            return playlistStore.myPlaylists
        case .user(let username):
            return playlistStore.playlists(for: username)
        }
    }

    private var isLoadingMusic: Bool {
        switch scope {
        case .ownProfile:
            return profileStore.isLoadingMusic && likedSongs.isEmpty && followingArtists.isEmpty
        case .user(let username):
            return profileStore.otherMusicLoadingUsernames.contains(normalizedUsername(username))
                && likedSongs.isEmpty
                && followingArtists.isEmpty
        }
    }

    private var isLoadingPlaylists: Bool {
        switch scope {
        case .ownProfile:
            return playlistStore.isLoadingMyPlaylists && playlists.isEmpty
        case .user(let username):
            return playlistStore.isLoadingUserPlaylistsByUsername.contains(normalizedUsername(username))
                && playlists.isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if isLoadingMusic {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            } else {
                songRail(
                    title: "Liked Songs",
                    songs: likedSongs,
                    emptyMessage: isOwnProfile
                        ? "Songs you like will show up here."
                        : "Liked songs will show up here."
                )

                artistRail(
                    title: "Following Artists",
                    artists: followingArtists,
                    emptyMessage: isOwnProfile
                        ? "Artists you follow will show up here."
                        : "Followed artists will show up here."
                )

                if isOwnProfile {
                    savedRail
                }
            }

            playlistsSection
        }
        .padding(.horizontal, -6)
        .task(id: scope) {
            await loadContent(force: false)
        }
    }

    private var savedRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfilePrivateSectionHeader(title: "Saved Tracks")

            if savedSongs.isEmpty {
                Text("Saved tracks are only visible to you.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(savedSongs.prefix(railItemLimit)), id: \.id) { song in
                            ProfileMusicSongCard(song: song)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    @ViewBuilder
    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            LibrarySectionHeader(title: "Playlists")

            if isLoadingPlaylists {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if playlists.isEmpty {
                Text(isOwnProfile
                     ? "No playlists yet."
                     : "No public playlists yet.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlistId: playlist.id)
                        } label: {
                            PlaylistRow(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if playlist.id == playlists.last?.id {
                                Task { await loadMorePlaylistsIfNeeded() }
                            }
                        }
                    }

                    if isLoadingMorePlaylists {
                        ProgressView()
                            .tint(.white)
                            .padding(.vertical, 16)
                    }
                }
            }
        }
    }

    private var isLoadingMorePlaylists: Bool {
        switch scope {
        case .ownProfile:
            return playlistStore.isLoadingMoreMyPlaylists
        case .user(let username):
            return playlistStore.isLoadingMoreUserPlaylistsByUsername.contains(normalizedUsername(username))
        }
    }

    @ViewBuilder
    private func songRail(title: String, songs: [ProfileMusicSong], emptyMessage: String) -> some View {
        LibraryHorizontalRail(
            title: title,
            emptyMessage: songs.isEmpty ? emptyMessage : nil
        ) {
            ForEach(Array(songs.prefix(railItemLimit)), id: \.id) { song in
                ProfileMusicSongCard(song: song)
            }
        }
    }

    @ViewBuilder
    private func artistRail(title: String, artists: [ProfileFollowingArtist], emptyMessage: String) -> some View {
        LibraryHorizontalRail(
            title: title,
            emptyMessage: artists.isEmpty ? emptyMessage : nil
        ) {
            ForEach(Array(artists.prefix(railItemLimit)), id: \.id) { artist in
                ProfileFollowingArtistCard(artist: artist)
            }
        }
    }

    private func loadContent(force: Bool) async {
        switch scope {
        case .ownProfile:
            async let music: Void = profileStore.loadMyMusic(force: force)
            async let playlists: Void = playlistStore.loadMyPlaylists(force: force)
            _ = await (music, playlists)
        case .user(let username):
            async let music: Void = profileStore.loadUserMusic(username: username, force: force)
            async let playlists: Void = playlistStore.loadUserPlaylists(username: username, force: force)
            _ = await (music, playlists)
        }
    }

    private func loadMorePlaylistsIfNeeded() async {
        switch scope {
        case .ownProfile:
            await playlistStore.loadMoreMyPlaylists()
        case .user(let username):
            await playlistStore.loadMoreUserPlaylists(username: username)
        }
    }

    private func normalizedUsername(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
