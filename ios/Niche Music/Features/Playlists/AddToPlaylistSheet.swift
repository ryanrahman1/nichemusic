//
//  AddToPlaylistSheet.swift
//  Niche Music
//

import Kingfisher
import SwiftUI

struct AddToPlaylistSheet: View {
    let trackId: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var playlistStore: PlaylistStore

    @State private var busyPlaylistIds: Set<String> = []
    @State private var errorMessage: String?

    private var isLoading: Bool {
        (playlistStore.isLoadingMyPlaylists && playlistStore.myPlaylists.isEmpty)
            || (playlistStore.loadingTrackMembershipIds.contains(trackId)
                && playlistStore.trackMembershipsByTrackId[trackId] == nil)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if playlistStore.myPlaylists.isEmpty {
                    ContentUnavailableView {
                        Label("No Playlists", systemImage: "music.note.list")
                    } description: {
                        Text("Create a playlist from your Library first.")
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(playlistStore.myPlaylists) { playlist in
                                Button {
                                    Task { await toggleMembership(for: playlist.id) }
                                } label: {
                                    playlistRow(playlist)
                                }
                                .buttonStyle(.plain)
                                .disabled(busyPlaylistIds.contains(playlist.id))

                                if playlist.id != playlistStore.myPlaylists.last?.id {
                                    Divider()
                                        .padding(.leading, 72)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
        }
        .task(id: trackId) {
            async let playlists: Void = playlistStore.loadMyPlaylists(
                force: playlistStore.myPlaylists.isEmpty
            )
            async let membership: Void = playlistStore.loadTrackMembership(trackId: trackId, force: true)
            _ = await (playlists, membership)
        }
    }

    @ViewBuilder
    private func playlistRow(_ playlist: PlaylistSummary) -> some View {
        let isMember = playlistStore.isTrackInPlaylist(trackId: trackId, playlistId: playlist.id)
        let isBusy = busyPlaylistIds.contains(playlist.id)

        HStack(spacing: 12) {
            playlistArtwork(playlist)

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(isMember ? "In playlist" : "Tap to add")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isBusy {
                ProgressView()
            } else if isMember {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)
            } else {
                Image(systemName: "plus.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func playlistArtwork(_ playlist: PlaylistSummary) -> some View {
        if let imageUrl = playlist.imageUrl, let url = URL(string: imageUrl) {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary)
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "music.note.list")
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func toggleMembership(for playlistId: String) async {
        guard !busyPlaylistIds.contains(playlistId) else { return }
        busyPlaylistIds.insert(playlistId)
        errorMessage = nil

        do {
            if let membership = playlistStore.membership(for: trackId, playlistId: playlistId) {
                try await playlistStore.removeTrack(
                    playlistId: playlistId,
                    trackId: trackId,
                    itemId: membership.itemId
                )
            } else {
                try await playlistStore.addTrack(playlistId: playlistId, trackId: trackId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        busyPlaylistIds.remove(playlistId)
    }
}
