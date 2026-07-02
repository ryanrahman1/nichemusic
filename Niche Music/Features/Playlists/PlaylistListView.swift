//
//  PlaylistListView.swift
//  Niche Music
//

import SwiftUI

struct PlaylistListView: View {
    @EnvironmentObject private var playlistStore: PlaylistStore

    @State private var showCreateSheet = false

    var body: some View {
        Group {
            if playlistStore.isLoadingMyPlaylists && playlistStore.myPlaylists.isEmpty {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = playlistStore.myPlaylistsError, playlistStore.myPlaylists.isEmpty {
                MusicDetailErrorState(message: error) {
                    Task { await playlistStore.loadMyPlaylists(force: true) }
                }
            } else if playlistStore.myPlaylists.isEmpty {
                VStack(spacing: 14) {
                    Text("No playlists yet")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Create a playlist to start collecting tracks.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)

                    Button("Create a playlist") {
                        showCreateSheet = true
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
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
                    .padding(.bottom, 120)
                }
            }
        }
        .background(Theme.backgroundColor.ignoresSafeArea())
        .navigationTitle("Playlists")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Theme.backgroundColor, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreatePlaylistView { _ in }
                .environmentObject(playlistStore)
        }
        .task {
            await playlistStore.loadMyPlaylists()
        }
        .refreshable {
            await playlistStore.loadMyPlaylists(force: true)
        }
    }
}
