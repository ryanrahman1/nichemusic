//
//  FeedActionRail.swift
//  Niche Music
//
//  Created by Ryan Rahman on 6/1/26.
//


//
//  FeedActionRail.swift
//  Niche Music
//

import SwiftUI
import Kingfisher

struct FeedActionRail: View {
    let likeCount: Int
    let commentCount: Int
    let repostCount: Int

    let isLiked: Bool
    let isReposted: Bool

    let artworkURL: URL?
    let ownerAvatarURL: URL?
    var trackReference: TrackDetailReference?

    private var railImageURL: URL? {
        artworkURL ?? ownerAvatarURL
    }

    var showPreviewControl: Bool = false
    var onPreviewToggle: (() -> Void)? = nil

    private let artworkCornerRadius: CGFloat = 6

    let onComment: () -> Void
    let onLike: () -> Void
    let onRepost: () -> Void
    var onLikeLongPress: (() -> Void)? = nil
    var onRepostLongPress: (() -> Void)? = nil

    /// Short enough to feel instant; long enough to avoid conflicting with tap-to-like.
    private let longPressDuration: Double = 0.35

    var body: some View {
        VStack(spacing: 22) {
            if showPreviewControl, let onPreviewToggle {
                FeedPreviewPlayPauseControl(action: onPreviewToggle)
            }

            actionButton(
                icon: isLiked ? "heart.fill" : "heart",
                count: likeCount,
                active: isLiked,
                action: onLike,
                longPressAction: onLikeLongPress
            )

            actionButton(
                icon: "bubble.right",
                count: commentCount,
                active: false,
                action: onComment
            )

            actionButton(
                icon: "arrow.2.squarepath",
                count: repostCount,
                active: isReposted,
                action: onRepost,
                longPressAction: onRepostLongPress
            )

            railThumbnailTile
        }
        .shadow(color: .black.opacity(0.7), radius: 8, y: 2)
    }

    @ViewBuilder
    private var railThumbnailTile: some View {
        if let trackReference, trackReference.canOpen {
            TrackDetailLink(reference: trackReference) {
                railThumbnailLabel
            }
        } else {
            railThumbnailLabel
        }
    }

    @ViewBuilder
    private var railThumbnailLabel: some View {
        Group {
            if let railImageURL {
                KFImage(railImageURL)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.12)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
        }
        .frame(width: 58)
    }

    private func actionButton(
        icon: String,
        count: Int,
        active: Bool,
        action: @escaping () -> Void,
        longPressAction: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(active ? .white : .white.opacity(0.92))

            Text(formatCount(count))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
        }
        .frame(width: 58)
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
        .onLongPressGesture(minimumDuration: longPressDuration, maximumDistance: 24) {
            guard let longPressAction else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            longPressAction()
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return "\(count / 1_000_000)M"
        }

        if count >= 10_000 {
            return "\(count / 1_000)K"
        }

        if count >= 1_000 {
            let value = Double(count) / 1_000
            return String(format: "%.1fK", value)
        }

        return "\(count)"
    }
}

/// Isolated so preview progress ticks don't rebuild the whole feed page and cancel taps.
private struct FeedPreviewPlayPauseControl: View {
    @ObservedObject private var feedPlayer = FeedPlayerCache.shared

    let action: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.28), lineWidth: 2.5)

            Circle()
                .trim(from: 0, to: min(1, max(0, feedPlayer.previewPlaybackProgress)))
                .stroke(
                    .white,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Image(systemName: feedPlayer.isPreviewPausedByUser ? "play.fill" : "pause.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .offset(x: feedPlayer.isPreviewPausedByUser ? 1 : 0)
        }
        .frame(width: 44, height: 44)
        .padding(7)
        .contentShape(Rectangle())
        .frame(width: 58, height: 58)
        .highPriorityGesture(
            TapGesture().onEnded {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action()
            }
        )
    }
}
