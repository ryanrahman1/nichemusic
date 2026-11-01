//
//  AppleMusicDetailView.swift
//  Niche Music
//

import Kingfisher
import SwiftUI

struct AppleMusicDetailView: View {
    let sourceId: String

    @State private var payload: AppleSongDetailResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var socialBusy = false
    @State private var loadTask: Task<Void, Never>?

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
                        shareURL: MusicShareLinks.track(payload.track.id),
                        shareTitle: payload.track.name,
                        reportTargetType: .track,
                        reportTargetId: payload.track.id
                    )
                }
            }
        }
        .onAppear { reload(force: false) }
        .onDisappear { loadTask?.cancel() }
    }

    @ViewBuilder
    private func loadedContent(_ data: AppleSongDetailResponse) -> some View {
        let blurURL = resolvedAppleArtworkURL(
            data.album?.artworkUrl ?? data.track.artworkUrl,
            size: 900
        )
        let trackArtURL = resolvedAppleArtworkURL(data.track.artworkUrl, size: 640)
        let previewURL = data.track.previewUrl.flatMap(URL.init(string:))

        MusicDetailScrollShell(artworkURL: blurURL) {
                Color.clear.frame(height: 12)

                heroArtwork(url: trackArtURL, previewURL: previewURL)

                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Text(data.track.name)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)

                        if let artist = data.artist {
                            NavigationLink {
                                AppleArtistDetailView(
                                    sourceId: artist.sourceId,
                                    ownerUsername: nil
                                )
                                .toolbarVisibility(.hidden, for: .tabBar)
                            } label: {
                                Text(artist.name)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.72))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    socialRow(data)

                    metaBlock(data)

                    if let appleURL = URL(string: "https://music.apple.com/us/song/\(data.track.sourceId)") {
                        AppleMusicOpenButton(url: appleURL)
                    }

                    if let copyright = data.album?.copyright, !copyright.isEmpty {
                        Text(copyright)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.white.opacity(0.38))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                lowerSections(data, trackArtURL: trackArtURL)
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 48)
        }
    }

    @ViewBuilder
    private func heroArtwork(url: URL?, previewURL: URL?) -> some View {
        ZStack {
            if let url {
                KFImage(url)
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
        .overlay {
            MusicPreviewPlayButton(previewURL: previewURL, isActive: true)
        }
    }

    private func socialRow(_ data: AppleSongDetailResponse) -> some View {
        HStack(spacing: 10) {
            MusicSocialStatButton(
                icon: "heart",
                filledIcon: "heart.fill",
                value: data.track.likeCount,
                isActive: data.viewer.isLiked,
                isDisabled: socialBusy
            ) {
                Task { await toggleLike(data) }
            }

            MusicSocialStatButton(
                icon: "bookmark",
                filledIcon: "bookmark.fill",
                value: data.track.saveCount,
                isActive: data.viewer.isSaved,
                isDisabled: socialBusy
            ) {
                Task { await toggleSave(data) }
            }

            ShareLink(item: MusicShareLinks.track(data.track.id), subject: Text(data.track.name)) {
                MusicSocialSharePill(count: data.track.shareCount)
            }
            .buttonStyle(.plain)
        }
    }

    private func metaBlock(_ data: AppleSongDetailResponse) -> some View {
        VStack(spacing: 8) {
            if let released = MusicDetailFormatters.shortDate(data.track.releaseDate) {
                Text("Released \(released)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }

            if let album = data.album {
                Text("Album · \(album.name)\(album.trackCount.map { " · \($0) tracks" } ?? "")")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private func lowerSections(_ data: AppleSongDetailResponse, trackArtURL: URL?) -> some View {
        if let artist = data.artist {
            VStack(alignment: .leading, spacing: 12) {
                MusicDetailSectionHeader(title: "Artist")

                NavigationLink {
                    AppleArtistDetailView(sourceId: artist.sourceId, ownerUsername: nil)
                        .toolbarVisibility(.hidden, for: .tabBar)
                } label: {
                    HStack(spacing: 12) {
                        if let url = resolvedAppleArtworkURL(artist.imageUrl, size: 120) {
                            KFImage(url)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 52, height: 52)
                                .clipShape(Circle())
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(artist.name)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white.opacity(0.9))

                            Text("\(MusicDetailFormatters.count(artist.fanCount ?? 0)) fans · \(MusicDetailFormatters.count(artist.shareCount)) shares")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.42))
                        }

                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 24)
        }

        if let album = data.album {
            VStack(alignment: .leading, spacing: 12) {
                MusicDetailSectionHeader(title: "About the album")

                if let albumArt = resolvedAppleArtworkURL(album.artworkUrl, size: 640),
                   albumArt.absoluteString != trackArtURL?.absoluteString {
                    KFImage(albumArt)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if let note = MusicDetailFormatters.stripHTML(album.editorialNote) {
                    Text(note)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineSpacing(4)
                }

                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "heart")
                            .font(.system(size: 14, weight: .semibold))
                        Text(MusicDetailFormatters.count(album.likeCount))
                            .font(.system(size: 14, weight: .bold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.white.opacity(0.72))

                    HStack(spacing: 6) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 14, weight: .semibold))
                        Text(MusicDetailFormatters.count(album.saveCount))
                            .font(.system(size: 14, weight: .bold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.white.opacity(0.72))
                }
            }
        }
    }

    private func reload(force: Bool) {
        loadTask?.cancel()
        loadTask = Task {
            isLoading = true
            if force { errorMessage = nil }

            do {
                let response = try await store.loadAppleSong(sourceId: sourceId, force: force)
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

    private func toggleLike(_ data: AppleSongDetailResponse) async {
        guard !socialBusy else { return }
        socialBusy = true
        let next = !data.viewer.isLiked
        let previous = payload

        payload = AppleSongDetailResponse(
            track: adjustedTrack(data.track, likeDelta: next ? 1 : -1, saveDelta: 0),
            artist: data.artist,
            album: data.album,
            viewer: TrackSocialViewer(isLiked: next, isSaved: data.viewer.isSaved)
        )

        do {
            try await store.setTrackLike(trackId: data.track.id, liked: next)
        } catch {
            payload = previous
        }

        socialBusy = false
    }

    private func toggleSave(_ data: AppleSongDetailResponse) async {
        guard !socialBusy else { return }
        socialBusy = true
        let next = !data.viewer.isSaved
        let previous = payload

        payload = AppleSongDetailResponse(
            track: adjustedTrack(data.track, likeDelta: 0, saveDelta: next ? 1 : -1),
            artist: data.artist,
            album: data.album,
            viewer: TrackSocialViewer(isLiked: data.viewer.isLiked, isSaved: next)
        )

        do {
            try await store.setTrackSave(trackId: data.track.id, saved: next)
        } catch {
            payload = previous
        }

        socialBusy = false
    }

    private func adjustedTrack(_ track: CatalogTrack, likeDelta: Int, saveDelta: Int) -> CatalogTrack {
        CatalogTrack(
            id: track.id,
            source: track.source,
            sourceId: track.sourceId,
            name: track.name,
            artworkUrl: track.artworkUrl,
            artistId: track.artistId,
            albumId: track.albumId,
            previewUrl: track.previewUrl,
            releaseDate: track.releaseDate,
            likeCount: max(0, track.likeCount + likeDelta),
            saveCount: max(0, track.saveCount + saveDelta),
            shareCount: track.shareCount,
            viewer: track.viewer,
            artistName: track.artistName
        )
    }
}
