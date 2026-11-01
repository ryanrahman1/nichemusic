//
//  AppleArtistDetailView.swift
//  Niche Music
//

import Kingfisher
import SwiftUI

struct AppleArtistDetailView: View {
    let sourceId: String
    var ownerUsername: String?

    @State private var payload: AppleArtistDetailResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var fanBusy = false
    @State private var discographyBusy = false
    @State private var loadTask: Task<Void, Never>?

    private let store = MusicDetailStore.shared

    var body: some View {
        Group {
            if let ownerUsername, !ownerUsername.isEmpty {
                OtherProfileView(username: ownerUsername)
                    .toolbarVisibility(.hidden, for: .tabBar)
            } else {
                catalogContent
            }
        }
    }

    private var catalogContent: some View {
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
                        shareURL: MusicShareLinks.artist(payload.artist.id),
                        shareTitle: payload.artist.name,
                        reportTargetType: .artist,
                        reportTargetId: payload.artist.id
                    )
                }
            }
        }
        .onAppear { reload(force: false) }
        .onDisappear { loadTask?.cancel() }
    }

    @ViewBuilder
    private func loadedContent(_ data: AppleArtistDetailResponse) -> some View {
        let imageURL = resolvedAppleArtworkURL(data.artist.imageUrl, size: 800)

        MusicDetailScrollShell(artworkURL: imageURL) {
                hero(data, imageURL: imageURL)
                    .padding(.top, 12)

                VStack(spacing: 24) {
                    fanRow(data)

                    if !data.albums.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            MusicDetailSectionHeader(title: "Albums")
                            ForEach(data.albums) { album in
                                CatalogAlbumRow(album: album)
                            }
                        }
                    }

                    if !data.songs.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            MusicDetailSectionHeader(title: "Songs")
                            ForEach(data.songs) { song in
                                CatalogTrackRow(track: song, showsArtist: false)
                            }
                        }
                    }

                    if let appleURL = URL(string: "https://music.apple.com/us/artist/\(data.artist.sourceId)") {
                        AppleMusicOpenButton(url: appleURL)
                    }

                    if !(data.artist.hasFullDiscography ?? false) {
                        Button {
                            Task { await loadDiscography() }
                        } label: {
                            Text(discographyBusy ? "Loading discography…" : "Load full discography")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(discographyBusy ? 0.35 : 0.45))
                                .underline(!discographyBusy)
                        }
                        .buttonStyle(.plain)
                        .disabled(discographyBusy)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 48)
        }
    }

    private func hero(_ data: AppleArtistDetailResponse, imageURL: URL?) -> some View {
        VStack(spacing: 14) {
            if let imageURL {
                KFImage(imageURL)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 160, height: 160)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            }

            Text(data.artist.name)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("\(MusicDetailFormatters.count(data.artist.fanCount ?? 0)) fans · \(MusicDetailFormatters.count(data.artist.shareCount)) shares")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
        }
        .padding(.top, 24)
    }

    private func fanRow(_ data: AppleArtistDetailResponse) -> some View {
        HStack(spacing: 10) {
            if !data.viewer.isOwner {
                Button {
                    Task { await toggleFan(data) }
                } label: {
                    Text(data.viewer.isFan ? "You are a fan" : "Become a fan")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(data.viewer.isFan ? .white : .black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(data.viewer.isFan ? .white.opacity(0.12) : .white, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(fanBusy)
            } else {
                Text("You manage this artist")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(.white.opacity(0.08), in: Capsule())
            }
        }
    }

    private func reload(force: Bool) {
        loadTask?.cancel()
        loadTask = Task {
            isLoading = true
            if force { errorMessage = nil }

            do {
                let response = try await store.loadAppleArtist(sourceId: sourceId, force: force)
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

    private func toggleFan(_ data: AppleArtistDetailResponse) async {
        guard !fanBusy else { return }
        fanBusy = true
        let next = !data.viewer.isFan
        let previous = payload

        payload = AppleArtistDetailResponse(
            artist: CatalogArtist(
                id: data.artist.id,
                source: data.artist.source,
                sourceId: data.artist.sourceId,
                name: data.artist.name,
                imageUrl: data.artist.imageUrl,
                ownerId: data.artist.ownerId,
                fanCount: max(0, (data.artist.fanCount ?? 0) + (next ? 1 : -1)),
                shareCount: data.artist.shareCount,
                hasFullDiscography: data.artist.hasFullDiscography
            ),
            viewer: ArtistSocialViewer(isFan: next, isOwner: data.viewer.isOwner),
            albums: data.albums,
            songs: data.songs
        )

        do {
            try await store.setArtistFan(artistId: data.artist.id, isFan: next)
        } catch {
            payload = previous
        }

        fanBusy = false
    }

    private func loadDiscography() async {
        guard !discographyBusy else { return }
        discographyBusy = true

        do {
            _ = try await store.loadAppleArtistDiscography(sourceId: sourceId)
            reload(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }

        discographyBusy = false
    }
}
