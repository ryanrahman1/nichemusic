//
//  PlaylistDetailView.swift
//  Niche Music
//

import Kingfisher
import SwiftUI

struct PlaylistDetailView: View {
    let playlistId: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var playlistStore: PlaylistStore
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var musicPlayer: MusicPlayer

    @State private var removingItemIds: Set<String> = []
    @State private var actionError: String?
    @State private var showEditPlaylist = false
    @State private var showDeleteConfirmation = false
    @State private var isDeletingPlaylist = false
    @State private var showAddTrackSearch = false

    private var detail: PlaylistDetail? {
        playlistStore.detailsById[playlistId]
    }

    private var isLoading: Bool {
        playlistStore.loadingDetailIds.contains(playlistId) && detail == nil
    }

    private var errorMessage: String? {
        playlistStore.detailErrorsById[playlistId]
    }

    private var isOwner: Bool {
        guard let detail, let userId = session.currentUser?.id else { return false }
        return detail.ownerId == userId
    }

    var body: some View {
        ZStack {
            if isLoading {
                MusicDetailLoadingState()
            } else if let errorMessage, detail == nil {
                MusicDetailErrorState(message: errorMessage) {
                    Task { await playlistStore.loadPlaylist(id: playlistId, force: true) }
                }
            } else if let detail {
                loadedContent(detail)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let detail {
                    PlaylistOptionsMenu(
                        playlist: detail,
                        isOwner: isOwner,
                        onEdit: { showEditPlaylist = true },
                        onAddTracks: { showAddTrackSearch = true },
                        onDelete: { showDeleteConfirmation = true }
                    )
                    .disabled(isDeletingPlaylist)
                }
            }
        }
        .navigationDestination(isPresented: $showAddTrackSearch) {
            PlaylistAddTrackSearchView(playlistId: playlistId)
                .environmentObject(playlistStore)
        }
        .sheet(isPresented: $showEditPlaylist) {
            if let detail {
                EditPlaylistView(playlist: detail)
                    .environmentObject(playlistStore)
            }
        }
        .confirmationDialog(
            "Delete this playlist?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Playlist", role: .destructive) {
                Task { await deletePlaylist() }
            }
        } message: {
            Text("This can't be undone.")
        }
        .task {
            await playlistStore.loadPlaylist(id: playlistId)
        }
        .refreshable {
            await refreshPlaylist()
        }
    }

    private func refreshPlaylist() async {
        // `.refreshable` cancels its task when the pull gesture ends, which would
        // abort the network request. Run refresh in an unstructured task instead.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task { @MainActor in
                defer { continuation.resume() }
                await playlistStore.loadPlaylist(id: playlistId, force: true)
            }
        }
    }

    @ViewBuilder
    private func loadedContent(_ detail: PlaylistDetail) -> some View {
        let artworkURL = detail.imageUrl.flatMap(URL.init(string:))

        MusicDetailScrollShell(artworkURL: artworkURL) {
            Color.clear.frame(height: 12)

            Group {
                if let artworkURL {
                    KFImage(artworkURL)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .overlay {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 42))
                                .foregroundStyle(.white.opacity(0.25))
                        }
                }
            }
            .frame(width: 280, height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)

            VStack(alignment: .leading, spacing: 22) {
                metadataSection(detail)

                if !detail.items.isEmpty {
                    Button {
                        PlaylistPlayback.playAll(
                            items: detail.items,
                            playlistId: playlistId,
                            playlistName: detail.name,
                            player: musicPlayer
                        )
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text("Play")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .liquidCapsuleGlass()
                    }
                    .buttonStyle(.plain)
                }

                if let actionError {
                    Text(actionError)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.red.opacity(0.85))
                }

                if detail.items.isEmpty {
                    Text("This playlist is empty. Add tracks from song pages to build it out.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineSpacing(3)
                } else {
                    MusicDetailSectionHeader(title: "Tracks")

                    LazyVStack(spacing: 0) {
                        ForEach(detail.items) { item in
                            PlaylistTrackRow(
                                item: item,
                                isOwner: isOwner,
                                isPlaying: musicPlayer.currentTrack?.id == item.track?.id && musicPlayer.isPlaying,
                                onPlay: {
                                    playItem(item, in: detail)
                                },
                                onRemove: isOwner ? {
                                    Task { await removeItem(item) }
                                } : nil
                            )
                            .disabled(removingItemIds.contains(item.id))
                            .opacity(removingItemIds.contains(item.id) ? 0.45 : 1)
                            .onAppear {
                                if item.id == detail.items.last?.id {
                                    Task { await playlistStore.loadMorePlaylistItems(id: playlistId) }
                                }
                            }
                        }

                        if playlistStore.loadingMoreDetailIds.contains(playlistId) {
                            ProgressView()
                                .tint(.white)
                                .padding(.vertical, 16)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 120)
        }
    }

    @ViewBuilder
    private func metadataSection(_ detail: PlaylistDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(detail.name)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)

            if let description = detail.description, !description.isEmpty {
                Text(description)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineSpacing(3)
            }

            if let owner = resolvedOwner(for: detail) {
                PlaylistOwnerRow(owner: owner)
            }

            HStack(spacing: 8) {
                Image(systemName: detail.visibility.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))

                Text(trackCountLabel(for: detail))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private func resolvedOwner(for detail: PlaylistDetail) -> PlaylistProfileRef? {
        if let owner = detail.owner {
            return owner
        }

        if detail.ownerId == session.currentUser?.id, let me = profileStore.me {
            return PlaylistProfileRef(
                id: me.id,
                username: me.username,
                displayName: me.displayName,
                avatarUrl: me.avatarUrl,
                isVerified: me.isVerified,
                verificationType: nil
            )
        }

        return detail.items.first?.track?.owner
    }

    private func trackCountLabel(for detail: PlaylistDetail) -> String {
        let count = detail.displayTrackCount
        return count == 1 ? "1 track" : "\(count) tracks"
    }

    private func playItem(_ item: PlaylistItem, in detail: PlaylistDetail) {
        guard item.track?.asNicheTrack() != nil else { return }
        PlaylistPlayback.play(
            items: detail.items,
            startingAt: item,
            playlistId: playlistId,
            playlistName: detail.name,
            player: musicPlayer
        )
    }

    private func removeItem(_ item: PlaylistItem) async {
        guard !removingItemIds.contains(item.id) else { return }
        removingItemIds.insert(item.id)

        do {
            try await playlistStore.removeItem(playlistId: playlistId, itemId: item.id)
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }

        removingItemIds.remove(item.id)
    }

    private func deletePlaylist() async {
        guard !isDeletingPlaylist else { return }
        isDeletingPlaylist = true
        actionError = nil

        do {
            try await playlistStore.deletePlaylist(id: playlistId)
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }

        isDeletingPlaylist = false
    }
}
