//
//  LibraryYourTabView.swift
//  Niche Music
//

import SwiftUI

struct LibraryYourTabView: View {
    @EnvironmentObject private var playlistStore: PlaylistStore

    @State private var showCreateSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LibrarySectionHeader(
                title: "Playlists",
                actionTitle: "Create",
                action: { showCreateSheet = true }
            )

            if playlistStore.isLoadingMyPlaylists && playlistStore.myPlaylists.isEmpty {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if playlistStore.myPlaylists.isEmpty {
                Text("No playlists yet. Create one to get started.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(playlistStore.myPlaylists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlistId: playlist.id)
                        } label: {
                            PlaylistRow(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if playlist.id == playlistStore.myPlaylists.last?.id {
                                Task { await playlistStore.loadMoreMyPlaylists() }
                            }
                        }
                    }

                    if playlistStore.isLoadingMoreMyPlaylists {
                        ProgressView()
                            .tint(.white)
                            .padding(.vertical, 16)
                    }
                }
            }

            if let error = playlistStore.myPlaylistsError, !playlistStore.myPlaylists.isEmpty {
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red.opacity(0.85))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreatePlaylistView { _ in }
                .environmentObject(playlistStore)
        }
    }
}
