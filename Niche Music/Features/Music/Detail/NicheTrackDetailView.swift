//
//  NicheTrackDetailView.swift
//  Niche Music
//

import Kingfisher
import SwiftUI

struct NicheTrackDetailView: View {
    let trackId: String

    @EnvironmentObject private var musicStore: MusicStore
    @EnvironmentObject private var musicPlayer: MusicPlayer
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var appNavigation: AppNavigationRouter
    @EnvironmentObject private var playlistStore: PlaylistStore
    @Environment(\.sheetPresentationContainerDismiss) private var sheetPresentationContainerDismiss

    @State private var track: NicheTrack?
    @State private var viewer = TrackViewer(isLiked: false, isSaved: false)
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var socialBusy = false
    @State private var showComments = false
    @State private var showAddToPlaylist = false
    @State private var isPlayingLocal = false
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if isLoading && track == nil {
                MusicDetailLoadingState()
            } else if let errorMessage, track == nil {
                MusicDetailErrorState(message: errorMessage) {
                    reload(force: true)
                }
            } else if let track {
                loadedContent(track)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let track {
                    MusicDetailOptionsMenu(
                        shareURL: MusicShareLinks.track(track.id),
                        shareTitle: track.name,
                        reportTargetType: .track,
                        reportTargetId: track.id
                    )
                }
            }
        }
        .sheet(isPresented: $showComments) {
            TrackCommentsView(trackId: trackId)
                .environmentObject(musicStore)
                .environmentObject(musicPlayer)
                .environmentObject(session)
                .environment(\.sheetExternalNavigation, appNavigation.sheetExternalNavigation(
                    dismiss: { showComments = false },
                    alsoDismissContainer: sheetPresentationContainerDismiss
                ))
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(trackId: trackId)
                .environmentObject(playlistStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear { reload(force: false) }
        .onChange(of: musicPlayer.isPlaying) { _, _ in
            syncPlayingState()
        }
        .onChange(of: musicPlayer.currentTrack?.id) { _, _ in
            syncPlayingState()
        }
        .onDisappear {
            loadTask?.cancel()
            if isPlayingLocal, musicPlayer.currentTrack?.id != trackId {
                musicPlayer.pause()
            }
        }
    }

    @ViewBuilder
    private func loadedContent(_ track: NicheTrack) -> some View {
        let artworkURL = URL(string: track.artworkUrl)

        MusicDetailScrollShell(artworkURL: artworkURL) {
            Color.clear.frame(height: 12)

            hero(track, artworkURL: artworkURL)

            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Text(track.name)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    TrackFeaturedArtistLine(
                        track: track,
                        font: .system(size: 17, weight: .semibold),
                        foreground: .white.opacity(0.72),
                        alignment: .center
                    )
                }

                socialRow(track)

                releaseDetails(track)

                playButton(track)

                commentsCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 48)
        }
    }

    @ViewBuilder
    private func hero(_ track: NicheTrack, artworkURL: URL?) -> some View {
        Group {
            if let artworkURL {
                KFImage(artworkURL)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.25))
                    }
            }
        }
        .frame(width: 280, height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
    }

    private func socialRow(_ track: NicheTrack) -> some View {
        HStack(spacing: 10) {
            MusicSocialStatButton(
                icon: "heart",
                filledIcon: "heart.fill",
                value: track.likeCount,
                isActive: viewer.isLiked,
                isDisabled: socialBusy
            ) {
                Task { await toggleLike(track) }
            }

            MusicSocialStatButton(
                icon: "bookmark",
                filledIcon: "bookmark.fill",
                value: track.saveCount,
                isActive: viewer.isSaved,
                isDisabled: socialBusy
            ) {
                Task { await toggleSave(track) }
            }

            ShareLink(item: MusicShareLinks.track(track.id), subject: Text(track.name)) {
                MusicSocialSharePill(count: track.shareCount)
            }
            .buttonStyle(.plain)

            Button {
                showAddToPlaylist = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))

                    Text("Playlist")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.white.opacity(0.07), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func releaseDetails(_ track: NicheTrack) -> some View {
        HStack(spacing: 10) {
            detailPill(title: "Released", value: MusicDetailFormatters.shortDate(track.releaseDate) ?? track.releaseDate)
            detailPill(title: "Length", value: MusicDetailFormatters.duration(ms: track.durationMs))
            if track.bpm > 0 {
                detailPill(title: "BPM", value: "\(track.bpm)")
            }
        }
    }

    private func detailPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.32))
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func playButton(_ track: NicheTrack) -> some View {
        Button {
            Task { await play(track) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isPlayingLocal ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                Text(isPlayingLocal ? "Pause" : "Play")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var commentsCard: some View {
        Button {
            showComments = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Comments")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))

                    Text("Join the conversation around this track.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.28))
            }
            .padding(16)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func syncPlayingState() {
        isPlayingLocal = musicPlayer.isPlaying && musicPlayer.currentTrack?.id == trackId
    }

    private func reload(force: Bool) {
        loadTask?.cancel()
        loadTask = Task {
            isLoading = true
            if force { errorMessage = nil }

            do {
                let loaded = try await musicStore.fetchTrackDetail(id: trackId, force: force)
                guard !Task.isCancelled else { return }
                track = loaded.track
                viewer = loaded.viewer
                errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                if track == nil {
                    errorMessage = error.localizedDescription
                }
            }

            isLoading = false
        }
    }

    private func play(_ track: NicheTrack) async {
        guard let url = URL(string: track.musicUrl) else { return }

        if musicPlayer.currentTrack?.id == track.id, musicPlayer.isPlaying {
            musicPlayer.pause()
            isPlayingLocal = false
            return
        }

        musicPlayer.playNow(track: track, url: url)
        isPlayingLocal = true
    }

    private func toggleLike(_ track: NicheTrack) async {
        guard !socialBusy else { return }
        socialBusy = true

        let next = !viewer.isLiked
        let previousViewer = viewer
        let previousTrack = self.track

        viewer = TrackViewer(isLiked: next, isSaved: viewer.isSaved)
        self.track = copyTrack(track, likeDelta: next ? 1 : -1, saveDelta: 0)

        do {
            try await MusicDetailStore.shared.setNicheTrackLike(trackId: track.id, liked: next)
        } catch {
            viewer = previousViewer
            self.track = previousTrack
        }

        socialBusy = false
    }

    private func toggleSave(_ track: NicheTrack) async {
        guard !socialBusy else { return }
        socialBusy = true

        let next = !viewer.isSaved
        let previousViewer = viewer
        let previousTrack = self.track

        viewer = TrackViewer(isLiked: viewer.isLiked, isSaved: next)
        self.track = copyTrack(track, likeDelta: 0, saveDelta: next ? 1 : -1)

        do {
            try await MusicDetailStore.shared.setNicheTrackSave(trackId: track.id, saved: next)
        } catch {
            viewer = previousViewer
            self.track = previousTrack
        }

        socialBusy = false
    }

    private func copyTrack(_ track: NicheTrack, likeDelta: Int, saveDelta: Int) -> NicheTrack {
        NicheTrack(
            id: track.id,
            ownerId: track.ownerId,
            name: track.name,
            artworkUrl: track.artworkUrl,
            musicUrl: track.musicUrl,
            releaseDate: track.releaseDate,
            explicit: track.explicit,
            featuredDurations: track.featuredDurations,
            hasLyrics: track.hasLyrics,
            durationMs: track.durationMs,
            popularity: track.popularity,
            bpm: track.bpm,
            gain: track.gain,
            createdAt: track.createdAt,
            updatedAt: track.updatedAt,
            deletedAt: track.deletedAt,
            visibility: track.visibility,
            likeCount: max(0, track.likeCount + likeDelta),
            saveCount: max(0, track.saveCount + saveDelta),
            shareCount: track.shareCount,
            owner: track.owner,
            momentUrl: track.momentUrl,
            credits: track.credits,
            metadata: track.metadata
        )
    }
}
