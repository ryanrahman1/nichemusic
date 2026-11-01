//
//  PlaylistSupport.swift
//  Niche Music
//

import Kingfisher
import SwiftUI

struct PlaylistCard: View {
    let playlist: PlaylistSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            artwork
                .frame(width: 132, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(playlist.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(playlist.visibility.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)
        }
        .frame(width: 132, alignment: .leading)
    }

    @ViewBuilder
    private var artwork: some View {
        if let imageUrl = playlist.imageUrl, let url = URL(string: imageUrl) {
            KFImage(url)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
        }
    }
}

struct PlaylistRow: View {
    let playlist: PlaylistSummary

    var body: some View {
        HStack(spacing: 14) {
            artwork
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let count = playlist.displayTrackCount
        if count == 1 {
            return "1 song"
        }
        if count > 1 {
            return "\(count) songs"
        }
        return "Playlist"
    }

    @ViewBuilder
    private var artwork: some View {
        if let imageUrl = playlist.imageUrl, let url = URL(string: imageUrl) {
            KFImage(url)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
        }
    }
}

struct PlaylistOwnerRow: View {
    let owner: PlaylistProfileRef

    var body: some View {
        ProfileUsernameLink(username: owner.username) {
            HStack(spacing: 10) {
                avatar

                Text(owner.displayName ?? owner.username)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarUrl = owner.avatarUrl, let url = URL(string: avatarUrl) {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
        }
    }
}

struct PlaylistTrackRow: View {
    let item: PlaylistItem
    let isOwner: Bool
    let isPlaying: Bool
    let onPlay: () -> Void
    let onRemove: (() -> Void)?

    private var track: PlaylistItemTrack? { item.track }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                HStack(spacing: 12) {
                    artwork

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if isPlaying {
                                PlayingBarsIndicator(color: Theme.accentColor, size: 15)
                            }

                            Text(track?.name ?? "Unavailable track")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(isPlaying ? Theme.accentColor : .white.opacity(0.92))
                                .lineLimit(1)
                        }

                        if let artistName = track?.primaryArtistName {
                            Text(artistName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let track, track.id != "" {
                NavigationLink {
                    NicheTrackDetailView(trackId: track.id)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.28))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .contextMenu {
            if isOwner, let onRemove {
                Button(role: .destructive, action: onRemove) {
                    Label("Remove from Playlist", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkUrl = track?.artworkUrl, let url = URL(string: artworkUrl) {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.white.opacity(0.28))
                }
        }
    }
}

enum PlaylistPlayback {
    private struct PlayableEntry {
        let itemId: String
        let queued: QueuedTrack
    }

    private static func entries(from items: [PlaylistItem], source: String) -> [PlayableEntry] {
        items.compactMap { item in
            guard
                let track = item.track?.asNicheTrack(),
                let url = URL(string: track.musicUrl)
            else {
                return nil
            }

            return PlayableEntry(
                itemId: item.id,
                queued: QueuedTrack(track: track, url: url, source: source)
            )
        }
    }

    static func playAll(items: [PlaylistItem], playlistId: String, playlistName: String, player: MusicPlayer) {
        let source = PlaybackSource.playlist(playlistName).label
        let queued = entries(from: items, source: source).map(\.queued)
        guard !queued.isEmpty else { return }
        player.playPlaylist(queued, startIndex: 0, source: source, playlistId: playlistId)
    }

    static func play(
        items: [PlaylistItem],
        startingAt item: PlaylistItem,
        playlistId: String,
        playlistName: String,
        player: MusicPlayer
    ) {
        let source = PlaybackSource.playlist(playlistName).label
        let playable = entries(from: items, source: source)
        guard let startIndex = playable.firstIndex(where: { $0.itemId == item.id }) else { return }
        player.playPlaylist(
            playable.map(\.queued),
            startIndex: startIndex,
            source: source,
            playlistId: playlistId
        )
    }
}
