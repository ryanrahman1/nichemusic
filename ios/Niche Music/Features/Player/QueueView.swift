//
//  QueueView.swift
//  Niche Music
//
//  Created by Ryan Rahman on 5/25/26.
//


import SwiftUI
import Kingfisher

struct QueueView: View {
    @EnvironmentObject var musicPlayer: MusicPlayer
    @EnvironmentObject var musicStore: MusicStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            playbackOptions

            if musicPlayer.queue.isEmpty {
                emptyState
            } else {
                queueList
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var displayedSource: String? {
        musicPlayer.sessionSource ?? musicPlayer.currentSource
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Up Next")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 10)

            Text(queueSubtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var queueSubtitle: String {
        let countLabel = "\(musicPlayer.queue.count) song\(musicPlayer.queue.count == 1 ? "" : "s")"
        if let source = displayedSource, !source.isEmpty {
            return "\(countLabel) · \(source)"
        }
        return countLabel
    }

    private var playbackOptions: some View {
        HStack(spacing: 10) {
            optionButton(
                icon: "shuffle",
                title: "Shuffle",
                isActive: musicPlayer.isShuffleEnabled
            ) {
                musicPlayer.toggleShuffle()
            }

            optionButton(
                icon: repeatIconName,
                title: repeatTitle,
                isActive: musicPlayer.repeatMode != .off
            ) {
                musicPlayer.toggleRepeat()
            }

            Spacer()
        }
    }

    private var repeatIconName: String {
        musicPlayer.repeatMode == .one ? "repeat.1" : "repeat"
    }

    private var repeatTitle: String {
        switch musicPlayer.repeatMode {
        case .off: "Repeat"
        case .all: "Repeat All"
        case .one: "Repeat One"
        }
    }

    private func optionButton(
        icon: String,
        title: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isActive ? Theme.accentColor : .white.opacity(0.72))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                (isActive ? Theme.accentColor.opacity(0.14) : .white.opacity(0.08)),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var queueList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                ForEach(musicPlayer.queue) { item in
                    Button {
                        musicPlayer.jumpToQueuedTrack(item)
                    } label: {
                        queueRow(item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func queueRow(_ item: QueuedTrack) -> some View {
        HStack(spacing: 12) {
            KFImage(URL(string: item.track.artworkUrl))
                .resizable()
                .scaledToFill()
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.track.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(resolvedTrack(for: item.track).displayArtistLine)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.25))
        }
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()

            Image(systemName: "music.note.list")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.white.opacity(0.25))

            Text("Nothing up next")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.65))

            Text("Songs you queue will show up here.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resolvedTrack(for track: NicheTrack) -> NicheTrack {
        musicStore.track(id: track.id) ?? track
    }
}
