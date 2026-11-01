//
//  FeedPostPageView.swift
//  Niche Music
//

import SwiftUI
import Kingfisher
import AVKit

struct FeedPostPageView: View {
    @EnvironmentObject private var musicPlayer: MusicPlayer

    let item: FeedItem
    let isActive: Bool

    let onLike: () -> Void
    let onRepost: () -> Void
    let onLikeLongPress: () -> Void
    let onRepostLongPress: () -> Void
    let onComment: () -> Void
    let onLongPress: () -> Void

    private var previewURLString: String? { item.post.previewAudioURL }
    private var hasPreviewAudio: Bool { item.post.showsPreviewPlaybackControl }

    private var showPreviewControl: Bool {
        isActive && hasPreviewAudio && !musicPlayer.isPlaying
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                background
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 0.35) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onLongPress()
                    }

                captionScrimGradient
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    ownerLine

                    if let reference = item.trackDetailReference, item.post.shouldShowProminentTrackTitle {
                        TrackDetailLink(reference: reference) {
                            trackBlock
                        }
                        .padding(.top, 10)
                    }

                    captionBlock
                        .padding(.top, 6)
                        .allowsHitTesting(false)
                }
                .padding(.leading, 22)
                .padding(.trailing, 92)
                .padding(.bottom, geo.safeAreaInsets.bottom + 112)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                FeedActionRail(
                    likeCount: item.post.likeCount,
                    commentCount: item.post.commentCount,
                    repostCount: item.post.repostCount,
                    isLiked: item.viewer.isLiked,
                    isReposted: item.viewer.isReposted,
                    artworkURL: item.post.railArtworkURL,
                    ownerAvatarURL: item.post.owner.avatarUrl.flatMap { URL(string: $0) },
                    trackReference: item.trackDetailReference,
                    showPreviewControl: showPreviewControl,
                    onPreviewToggle: {
                        FeedPlayerCache.shared.togglePreviewPaused()
                    },
                    onComment: onComment,
                    onLike: onLike,
                    onRepost: onRepost,
                    onLikeLongPress: onLikeLongPress,
                    onRepostLongPress: onRepostLongPress
                )
                .padding(.trailing, 14)
                .padding(.bottom, geo.safeAreaInsets.bottom + 112)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .zIndex(1)
            }
        }
        .ignoresSafeArea()
    }

    private var captionScrimGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.55),
                .init(color: .black.opacity(0.45), location: 0.78),
                .init(color: .black.opacity(0.88), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder
    private var background: some View {
        ZStack {
            if let imageURL = item.post.primaryDisplayImageURL {
                KFImage(imageURL)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Color.black
            }

            if item.post.isPMO, let momentURL = item.post.momentVisualURL {
                let cacheKey = FeedPlayerMediaKind.moment.cacheKey(for: momentURL)
                FeedVideoPlayer(
                    player: FeedPlayerCache.shared.player(for: cacheKey),
                    contentMode: .fit
                )
            }

            if let videoURL = item.post.uploadedVideoURL {
                FeedVideoPlayer(
                    player: FeedPlayerCache.shared.player(for: videoURL),
                    contentMode: .fill
                )
            }
        }
    }

    private var ownerLine: some View {
        ProfileUsernameLink(username: item.post.owner.username) {
            HStack(spacing: 10) {
                if let avatarUrl = item.post.owner.avatarUrl,
                   let url = URL(string: avatarUrl) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(.white.opacity(0.14))
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                }

                Text("@\(item.post.owner.username)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    private var trackBlock: some View {
        if let track = item.post.track {
            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(track.artist.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        } else if let track = item.post.content.track {
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title ?? track.name ?? "Track")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let artistName = track.artistName, !artistName.isEmpty {
                    Text(artistName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        } else if let nicheTrack = item.post.resolvedNicheTrack {
            VStack(alignment: .leading, spacing: 3) {
                Text(nicheTrack.displayTitle)
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if !nicheTrack.displayArtistName.isEmpty {
                    Text("@\(nicheTrack.displayArtistName)")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private var captionBlock: some View {
        if let caption = item.post.content.caption,
           !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(caption)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)
        }
    }
}
