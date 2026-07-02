//
//  NicheAlbumDetailView.swift
//  Niche Music
//

import Kingfisher
import SwiftUI

struct NicheAlbumDetailView: View {
    let albumId: String

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var musicPlayer: MusicPlayer

    @State private var payload: NicheAlbumDetailResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var socialBusy = false
    @State private var loadTask: Task<Void, Never>?
    @State private var shouldRefreshAfterEdit = false

    private let store = MusicDetailStore.shared

    var body: some View {
        ZStack {
            if isLoading && payload == nil {
                MusicDetailLoadingState()
            } else if let errorMessage, payload == nil {
                MusicDetailErrorState(message: errorMessage) {
                    reload(force: true)
                }
            } else if let payload {
                loadedContent(payload)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let payload {
                    MusicDetailOptionsMenu(
                        shareURL: MusicShareLinks.album(payload.album.id),
                        shareTitle: payload.album.name,
                        reportTargetType: .album,
                        reportTargetId: payload.album.id
                    )
                }
            }
        }
        .onAppear {
            if shouldRefreshAfterEdit {
                shouldRefreshAfterEdit = false
                reload(force: true)
            } else {
                reload(force: false)
            }
        }
        .onDisappear { loadTask?.cancel() }
    }

    @ViewBuilder
    private func loadedContent(_ data: NicheAlbumDetailResponse) -> some View {
        let artworkURL = URL(string: data.album.artworkUrl)

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
                            Image(systemName: "square.stack")
                                .font(.system(size: 42))
                                .foregroundStyle(.white.opacity(0.25))
                        }
                }
            }
            .frame(width: 280, height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)

            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(data.album.name)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)

                    ProfileUsernameLink(username: data.owner.username) {
                        Text(data.owner.displayName ?? data.owner.username)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.accentColor)
                    }

                    Text(releaseMetadataText(for: data.album))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }

                albumSocialRow(data)

                if !data.tracks.isEmpty {
                    MusicDetailSectionHeader(title: "Tracks")

                    LazyVStack(spacing: 0) {
                        ForEach(sortedTracks(from: data.tracks)) { track in
                            NicheAlbumTrackRowView(
                                track: track,
                                owner: data.owner,
                                isPlaying: musicPlayer.currentTrack?.id == track.id && musicPlayer.isPlaying,
                                canEdit: isAlbumOwner(data),
                                onPlay: {
                                    playTrack(track, in: data)
                                },
                                onEdit: {
                                    shouldRefreshAfterEdit = true
                                }
                            )
                            Divider().overlay(.white.opacity(0.06))
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 48)
        }
    }

    private func albumSocialRow(_ data: NicheAlbumDetailResponse) -> some View {
        HStack(spacing: 10) {
            MusicSocialStatButton(
                icon: "heart",
                filledIcon: "heart.fill",
                value: data.album.likeCount,
                isActive: data.viewer.isLiked,
                isDisabled: socialBusy
            ) {
                Task { await toggleLike(data) }
            }

            MusicSocialStatButton(
                icon: "bookmark",
                filledIcon: "bookmark.fill",
                value: data.album.saveCount,
                isActive: data.viewer.isSaved,
                isDisabled: socialBusy
            ) {
                Task { await toggleSave(data) }
            }

            ShareLink(item: MusicShareLinks.album(data.album.id), subject: Text(data.album.name)) {
                MusicSocialSharePill(count: data.album.shareCount)
            }
            .buttonStyle(.plain)
        }
    }

    private func reload(force: Bool) {
        loadTask?.cancel()
        loadTask = Task {
            isLoading = true
            if force { errorMessage = nil }

            do {
                let response = try await store.loadNicheAlbum(id: albumId, force: force)
                guard !Task.isCancelled else { return }
                payload = response
                errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                if payload == nil {
                    errorMessage = error.localizedDescription
                }
            }

            isLoading = false
        }
    }

    private func toggleLike(_ data: NicheAlbumDetailResponse) async {
        guard !socialBusy else { return }
        socialBusy = true
        let next = !data.viewer.isLiked
        let previous = payload

        payload = NicheAlbumDetailResponse(
            album: copyAlbum(data.album, likeDelta: next ? 1 : -1, saveDelta: 0),
            owner: data.owner,
            viewer: AlbumSocialViewer(isLiked: next, isSaved: data.viewer.isSaved),
            tracks: data.tracks
        )

        do {
            try await store.setAlbumLike(albumId: data.album.id, liked: next)
        } catch {
            payload = previous
        }

        socialBusy = false
    }

    private func toggleSave(_ data: NicheAlbumDetailResponse) async {
        guard !socialBusy else { return }
        socialBusy = true
        let next = !data.viewer.isSaved
        let previous = payload

        payload = NicheAlbumDetailResponse(
            album: copyAlbum(data.album, likeDelta: 0, saveDelta: next ? 1 : -1),
            owner: data.owner,
            viewer: AlbumSocialViewer(isLiked: data.viewer.isLiked, isSaved: next),
            tracks: data.tracks
        )

        do {
            try await store.setAlbumSave(albumId: data.album.id, saved: next)
        } catch {
            payload = previous
        }

        socialBusy = false
    }

    private func copyAlbum(_ album: NicheAlbumSummary, likeDelta: Int, saveDelta: Int) -> NicheAlbumSummary {
        NicheAlbumSummary(
            id: album.id,
            name: album.name,
            artworkUrl: album.artworkUrl,
            ownerId: album.ownerId,
            releaseDate: album.releaseDate,
            releaseType: album.releaseType,
            trackCount: album.trackCount,
            likeCount: max(0, album.likeCount + likeDelta),
            saveCount: max(0, album.saveCount + saveDelta),
            shareCount: album.shareCount
        )
    }

    private func isAlbumOwner(_ data: NicheAlbumDetailResponse) -> Bool {
        guard let userId = session.currentUser?.id else { return false }
        return data.owner.id == userId
    }

    private func sortedTracks(from tracks: [NicheAlbumTrackRow]) -> [NicheAlbumTrackRow] {
        tracks.sorted {
            ($0.trackNumber ?? Int.max) < ($1.trackNumber ?? Int.max)
        }
    }

    private func playTrack(_ track: NicheAlbumTrackRow, in data: NicheAlbumDetailResponse) {
        NicheAlbumPlayback.play(
            tracks: sortedTracks(from: data.tracks),
            startingAt: track,
            albumName: data.album.name,
            owner: data.owner,
            player: musicPlayer
        )
    }

    private func releaseMetadataText(for album: NicheAlbumSummary) -> String {
        var parts: [String] = []

        if let date = MusicDetailFormatters.shortDate(album.releaseDate) {
            parts.append(date)
        }

        parts.append(releaseTypeLabel(for: album))
        parts.append(album.trackCount == 1 ? "1 track" : "\(album.trackCount) tracks")

        return parts.joined(separator: " · ")
    }

    private func releaseTypeLabel(for album: NicheAlbumSummary) -> String {
        switch album.releaseType?.lowercased() {
        case "ep": "EP"
        case "album": "Album"
        default: "Release"
        }
    }
}
