//
//  MiniPlayerPlaceholderView.swift
//  Niche Music
//
//  Created by Ryan Rahman on 5/24/26.
//

import SwiftUI
import Kingfisher

struct MiniPlayerView: View {
    @EnvironmentObject var musicPlayer: MusicPlayer
    @EnvironmentObject var musicStore: MusicStore
    @Binding var showFullPlayer: Bool
    var tabBarMinimized = false

    private var displayTrack: NicheTrack? {
        guard let trackId = musicPlayer.currentTrack?.id else { return nil }
        return musicStore.track(id: trackId) ?? musicPlayer.currentTrack
    }

    var body: some View {
        HStack(spacing: 14) {
            Button {
                showFullPlayer = true
            } label: {
                HStack(spacing: 14) {
                    artwork(size: 40, radius: 6)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            MarqueeText(
                                text: musicPlayer.currentTrack?.name ?? "Nothing Playing",
                                font: .system(size: 14, weight: .semibold),
                                foreground: .white
                            )
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                            if musicPlayer.currentTrack?.explicit == true {
                                ExplicitBadge()
                            }
                        }

                        MarqueeText(
                            text: displayTrack?.displayArtistLine ?? "—",
                            font: .system(size: 12, weight: .regular),
                            foreground: .white.opacity(0.5)
                        )
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                if musicPlayer.isLoading {
                    NicheProgress()
                        .scaleEffect(0.8)
                        .frame(width: 36, height: 36)
                } else {
                    Button {
                        musicPlayer.togglePlayPause()
                    } label: {
                        Image(systemName: musicPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if !tabBarMinimized {
                    Button {
                        musicPlayer.skipToNext()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            progressBar
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: tabBarMinimized)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.white.opacity(0.15))
                    .frame(height: 2)

                Rectangle()
                    .fill(.white)
                    .frame(
                        width: musicPlayer.duration > 0
                            ? geo.size.width * CGFloat(musicPlayer.currentTime / musicPlayer.duration)
                            : 0,
                        height: 2
                    )
            }
        }
        .frame(height: 2)
        .allowsHitTesting(false)
    }

    private func artwork(size: CGFloat, radius: CGFloat) -> some View {
        Group {
            if let coverUrl = musicPlayer.currentTrack?.artworkUrl,
               let url = URL(string: coverUrl) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
