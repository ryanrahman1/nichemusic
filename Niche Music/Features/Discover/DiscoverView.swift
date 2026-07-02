//
//  DiscoverView.swift
//  Niche Music
//

import SwiftUI

struct DiscoverView: View {
    @StateObject private var searchStore = DiscoverSearchStore()
    @StateObject private var discoverStore = DiscoverStore()
    @EnvironmentObject private var playlistStore: PlaylistStore

    @State private var isSearchActive = false
    @State private var query = ""
    @State private var selectedSuggestion: GlobalSearchSuggestion?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                ZStack {
                    if !isSearchActive {
                        discoverContent
                            .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    }

                    if isSearchActive {
                        searchContent
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.24), value: isSearchActive)
            }
            .background(Theme.backgroundColor.ignoresSafeArea())
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedSuggestion) { suggestion in
                DiscoverSearchSuggestionDestination(suggestion: suggestion)
                    .environmentObject(playlistStore)
            }
            .onChange(of: query) { _, newValue in
                searchStore.updateQuery(newValue)
            }
            .task {
                await discoverStore.loadHome()
            }
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 12) {
            DiscoverSearchField(
                text: $query,
                placeholder: "Search artists, songs, playlists",
                isActive: isSearchActive,
                onActivate: {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        isSearchActive = true
                    }
                },
                onSubmit: {
                    Task {
                        await searchStore.loadResults(query: query)
                    }
                }
            )

            if isSearchActive {
                Button("Cancel") {
                    closeSearch()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.24), value: isSearchActive)
    }

    private var discoverContent: some View {
        DiscoverHomeContent(store: discoverStore)
    }

    @ViewBuilder
    private var searchContent: some View {
        if searchStore.isLoadingResults {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = searchStore.errorMessage, searchStore.results == nil {
            searchError(error) {
                Task {
                    if !searchStore.activeQuery.isEmpty {
                        await searchStore.loadResults(query: searchStore.activeQuery)
                    } else {
                        await searchStore.loadSuggestions(query: query)
                    }
                }
            }
        } else if let results = searchStore.results {
            fullResultsList(results)
        } else {
            suggestionsList
        }
    }

    @ViewBuilder
    private var suggestionsList: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            searchPlaceholder("Search for artists, songs, playlists, and profiles.")
        } else if trimmed.count < 2 {
            searchPlaceholder("Keep typing to see suggestions.")
        } else if searchStore.isLoadingSuggestions && searchStore.suggestions.isEmpty {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = searchStore.errorMessage, searchStore.suggestions.isEmpty {
            searchError(error) {
                Task { await searchStore.loadSuggestions(query: trimmed) }
            }
        } else if searchStore.suggestions.isEmpty {
            searchPlaceholder("No suggestions for \"\(trimmed)\".")
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(searchStore.suggestions) { suggestion in
                        DiscoverSearchSuggestionRow(suggestion: suggestion) {
                            selectedSuggestion = suggestion
                        }
                    }
                }
                .padding(.bottom, 120)
            }
        }
    }

    @ViewBuilder
    private func fullResultsList(_ results: GlobalSearchResults) -> some View {
        if results.isEmpty {
            searchPlaceholder("No results for \"\(searchStore.activeQuery)\".")
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    if !results.profiles.isEmpty {
                        DiscoverSearchSectionHeader(title: "Profiles")
                        ForEach(results.profiles) { profile in
                            ProfileUsernameLink(username: profile.username) {
                                DiscoverSearchResultRow(
                                    title: profile.displayName ?? profile.username,
                                    subtitle: "@\(profile.username)",
                                    imageUrl: profile.avatarUrl
                                )
                            }
                        }
                    }

                    if !results.artists.isEmpty {
                        DiscoverSearchSectionHeader(title: "Artists")
                        ForEach(results.artists) { artist in
                            NavigationLink {
                                AppleArtistDetailView(
                                    sourceId: artist.sourceId ?? artist.id,
                                    ownerUsername: nil
                                )
                                .toolbarVisibility(.hidden, for: .tabBar)
                            } label: {
                                DiscoverSearchResultRow(
                                    title: artist.name,
                                    subtitle: "Artist",
                                    imageUrl: artist.imageUrl,
                                    artworkType: "artist",
                                    sourceMark: artist.source == "apple_music" ? .appleMusic : nil
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !results.nicheTracks.isEmpty {
                        DiscoverSearchSectionHeader(title: "Niche Songs")
                        ForEach(results.nicheTracks) { track in
                            NavigationLink {
                                NicheTrackDetailView(trackId: track.id)
                                    .toolbarVisibility(.hidden, for: .tabBar)
                            } label: {
                                DiscoverSearchResultRow(
                                    title: track.name,
                                    subtitle: track.displayArtistName,
                                    imageUrl: track.artworkUrl,
                                    sourceMark: .niche
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !results.tracks.isEmpty {
                        DiscoverSearchSectionHeader(title: "Songs")
                        ForEach(results.tracks) { track in
                            TrackDetailLink(
                                reference: TrackDetailReference(
                                    id: track.id,
                                    source: track.source,
                                    sourceId: track.sourceId
                                )
                            ) {
                                DiscoverSearchResultRow(
                                    title: track.name,
                                    subtitle: track.artist?.name,
                                    imageUrl: track.artworkUrl,
                                    sourceMark: track.source == "apple_music" ? .appleMusic : nil
                                )
                            }
                        }
                    }

                    if !results.albums.isEmpty {
                        DiscoverSearchSectionHeader(title: "Albums")
                        ForEach(results.albums) { album in
                            NavigationLink {
                                AppleAlbumDetailView(sourceId: album.sourceId ?? album.id)
                                    .toolbarVisibility(.hidden, for: .tabBar)
                            } label: {
                                DiscoverSearchResultRow(
                                    title: album.name,
                                    subtitle: album.artist?.name,
                                    imageUrl: album.artworkUrl,
                                    artworkType: "album",
                                    sourceMark: album.source == "apple_music" ? .appleMusic : nil
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !results.playlists.isEmpty {
                        DiscoverSearchSectionHeader(title: "Playlists")
                        ForEach(results.playlists) { playlist in
                            NavigationLink {
                                PlaylistDetailView(playlistId: playlist.id)
                                    .toolbarVisibility(.hidden, for: .tabBar)
                            } label: {
                                DiscoverSearchResultRow(
                                    title: playlist.name,
                                    subtitle: playlist.owner?.displayName ?? playlist.owner?.username,
                                    imageUrl: playlist.imageUrl
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !results.badges.isEmpty {
                        DiscoverSearchSectionHeader(title: "Badges")
                        ForEach(results.badges) { badge in
                            NavigationLink {
                                BadgeDetailView(
                                    badgeId: badge.id,
                                    initialBadge: badge.asBadgeDetail
                                )
                                .toolbarVisibility(.hidden, for: .tabBar)
                            } label: {
                                DiscoverSearchBadgeResultRow(badge: badge)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, 120)
            }
        }
    }

    private func searchPlaceholder(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white.opacity(0.45))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func searchError(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            Button("Try again", action: retry)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accentColor)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func closeSearch() {
        withAnimation(.easeInOut(duration: 0.24)) {
            isSearchActive = false
        }
        query = ""
        searchStore.reset()
    }
}

#Preview {
    DiscoverView()
        .environmentObject(PlaylistStore())
}
