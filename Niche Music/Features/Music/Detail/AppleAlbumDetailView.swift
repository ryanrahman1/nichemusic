//
//  AppleAlbumDetailView.swift
//  Niche Music
//

import Kingfisher
import SwiftUI

struct AppleAlbumDetailView: View {
    let sourceId: String

    @State private var payload: AppleAlbumDetailResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isSyncing = false
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
                        shareURL: MusicShareLinks.album(payload.album.id),
                        shareTitle: payload.album.name,
                        reportTargetType: .album,
                        reportTargetId: payload.album.id
                    )
                }
            }
        }
        .onAppear { reload(force: false) }
        .onDisappear { loadTask?.cancel() }
    }

    @ViewBuilder
    private func loadedContent(_ data: AppleAlbumDetailResponse) -> some View {
        let blurURL = resolvedAppleArtworkURL(data.album.artworkUrl, size: 900)
        let artworkURL = resolvedAppleArtworkURL(data.album.artworkUrl, size: 640)

        MusicDetailScrollShell(artworkURL: blurURL) {
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

                    if let artist = data.artist {
                        NavigationLink {
                            AppleArtistDetailView(sourceId: artist.sourceId, ownerUsername: nil)
                                .toolbarVisibility(.hidden, for: .tabBar)
                        } label: {
                            Text(artist.name)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.accentColor)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 12) {
                        if let date = MusicDetailFormatters.shortDate(data.album.releaseDate) {
                            Text(date)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                        }

                        if let count = data.album.trackCount {
                            Text("\(count) tracks")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }

                if let note = MusicDetailFormatters.stripHTML(data.album.editorialNote) {
                    Text(note)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineSpacing(4)
                }

                if !data.songs.isEmpty {
                    MusicDetailSectionHeader(title: "Tracks")

                    LazyVStack(spacing: 0) {
                        ForEach(data.songs) { song in
                            CatalogTrackRow(track: song, showsArtist: false)
                            Divider().overlay(.white.opacity(0.06))
                        }
                    }
                }

                if let appleURL = URL(string: "https://music.apple.com/us/album/\(data.album.sourceId)") {
                    AppleMusicOpenButton(url: appleURL)
                }

                Button {
                    Task { await syncAlbum() }
                } label: {
                    Text(isSyncing ? "Syncing with Apple Music…" : "Sync with Apple Music")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(isSyncing ? 0.35 : 0.45))
                        .underline(!isSyncing)
                }
                .buttonStyle(.plain)
                .disabled(isSyncing)
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 48)
        }
    }

    private func reload(force: Bool) {
        loadTask?.cancel()
        loadTask = Task {
            isLoading = true
            if force { errorMessage = nil }

            do {
                let response = try await store.loadAppleAlbum(sourceId: sourceId, force: force)
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

    private func syncAlbum() async {
        guard !isSyncing else { return }
        isSyncing = true

        do {
            let ok = try await store.syncAppleAlbum(sourceId: sourceId)
            if ok {
                reload(force: true)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isSyncing = false
    }
}
