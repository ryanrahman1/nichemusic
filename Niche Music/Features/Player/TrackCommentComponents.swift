//
//  TrackCommentComponents.swift
//  Niche Music
//

import SwiftUI
import Kingfisher

struct TrackCommentComposerBar: View {
    @Binding var draft: String
    let replyTarget: TrackComment?
    let onCancelReply: () -> Void
    let onSendText: () -> Void
    let onAttachTrack: () -> Void
    let onAttachGIF: () -> Void
    let isSending: Bool

    var body: some View {
        VStack(spacing: 8) {
            if let replyTarget {
                HStack {
                    Text("Replying to @\(replyTarget.owner.username)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel", action: onCancelReply)
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 16)
            }

            HStack(spacing: 10) {
                Menu {
                    Button("Track", action: onAttachTrack)
                    Button("GIF", action: onAttachGIF)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.75))
                        .frame(width: 36, height: 36)
                        .background(.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isSending)

                TextField("Add a comment...", text: $draft)
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(.primary.opacity(0.06), in: Capsule())
                    .disabled(isSending)

                Button(action: onSendText) {
                    if isSending {
                        ProgressView()
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(
                                draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? .secondary
                                    : Theme.accentColor
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .padding(.top, 10)
    }
}

struct TrackCommentRowView: View {
    @EnvironmentObject private var commentsStore: TrackCommentsStore
    @EnvironmentObject private var session: SessionStore

    let comment: TrackComment
    let trackId: String
    let trackOwnerId: String
    let viewerOwnsTrack: Bool
    let parentCommentId: String?
    var onOpenProfile: ((String) -> Void)?
    let onReply: () -> Void
    let onViewReplies: (() -> Void)?

    @State private var showOptions = false

    init(
        comment: TrackComment,
        trackId: String,
        trackOwnerId: String,
        viewerOwnsTrack: Bool,
        parentCommentId: String? = nil,
        onOpenProfile: ((String) -> Void)? = nil,
        onReply: @escaping () -> Void,
        onViewReplies: (() -> Void)?
    ) {
        self.comment = comment
        self.trackId = trackId
        self.trackOwnerId = trackOwnerId
        self.viewerOwnsTrack = viewerOwnsTrack
        self.parentCommentId = parentCommentId
        self.onOpenProfile = onOpenProfile
        self.onReply = onReply
        self.onViewReplies = onViewReplies
    }

    private var canManageComment: Bool {
        viewerOwnsTrack
            || comment.ownerId == session.currentUser?.id
            || comment.viewer?.isOwner == true
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            avatar

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .center, spacing: 6) {
                    profileLink(username: comment.owner.username) {
                        Text(comment.owner.displayName ?? comment.owner.username)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    Text("@\(comment.owner.username)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    if comment.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.accentColor)
                    }

                    Spacer(minLength: 6)

                    Text(relativeDate(comment.createdAt))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                commentBody

                HStack(spacing: 16) {
                    Button {
                        Task { await commentsStore.toggleLike(trackId: trackId, commentId: comment.id) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: comment.viewer?.isLiked == true ? "heart.fill" : "heart")
                            Text(comment.likeCount > 0 ? "\(comment.likeCount)" : "Like")
                        }
                    }

                    Button(action: onReply) {
                        Text(comment.replyCount > 0 ? "\(comment.replyCount) replies" : "Reply")
                    }

                    if comment.replyCount > 0, let onViewReplies {
                        Button("View replies", action: onViewReplies)
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)

                if comment.isHidden && viewerOwnsTrack {
                    Text("Hidden from listeners")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange.opacity(0.85))
                }
            }
        }
        .opacity(comment.isHidden ? 0.55 : 1)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.35) {
            if canManageComment {
                showOptions = true
            }
        }
        .confirmationDialog("Comment Options", isPresented: $showOptions, titleVisibility: .visible) {
            if viewerOwnsTrack {
                Button(comment.isPinned ? "Unpin comment" : "Pin comment") {
                    Task {
                        try? await commentsStore.setPinned(
                            trackId: trackId,
                            commentId: comment.id,
                            pinned: !comment.isPinned
                        )
                    }
                }
                Button(comment.isHidden ? "Unhide comment" : "Hide comment", role: .destructive) {
                    Task {
                        try? await commentsStore.setHidden(
                            trackId: trackId,
                            commentId: comment.id,
                            hidden: !comment.isHidden
                        )
                    }
                }
            }
            if canManageComment {
                Button("Delete comment", role: .destructive) {
                    Task {
                        try? await commentsStore.deleteComment(
                            trackId: trackId,
                            commentId: comment.id,
                            parentCommentId: parentCommentId
                        )
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var commentBody: some View {
        switch comment.content.kind {
        case .text:
            if let replyToUser = comment.replyToUser {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    profileLink(username: replyToUser.username) {
                        Text("@\(replyToUser.username) ")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.accentColor)
                    }
                    Text(comment.content.text ?? "")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.primary)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(comment.content.text ?? "")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .gif:
            if let gif = comment.content.gif,
               let url = URL(string: gif.url) {
                KFAnimatedImage(url)
                    .scaledToFill()
                    .frame(width: 190, height: gifHeight(gif))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Text("GIF unavailable")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

        case .track:
            if let track = comment.content.track {
                TrackDetailLink(reference: TrackDetailReference(track)) {
                    sharedTrackCard(track)
                }
            } else {
                Text("Track unavailable")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var avatar: some View {
        Group {
            if let avatarUrl = comment.owner.avatarUrl,
               let url = URL(string: avatarUrl) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(.primary.opacity(0.08))
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
    }

    @ViewBuilder
    private func profileLink<Label: View>(
        username: String,
        @ViewBuilder label: @escaping () -> Label
    ) -> some View {
        if let onOpenProfile {
            Button {
                onOpenProfile(username)
            } label: {
                label()
            }
            .buttonStyle(.plain)
        } else {
            ProfileUsernameLink(username: username) {
                label()
            }
        }
    }

    private func sharedTrackCard(_ track: TrackCommentSharedTrack) -> some View {
        HStack(spacing: 10) {
            if let artworkUrl = track.artworkUrl,
               let url = URL(string: artworkUrl.replacingOccurrences(of: "{w}x{h}", with: "120x120")) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.primary.opacity(0.08))
                    .frame(width: 46, height: 46)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(track.artistName ?? "Unknown Artist")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "music.note")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func gifHeight(_ gif: TrackCommentGif) -> CGFloat {
        guard let width = gif.width,
              let height = gif.height,
              width > 0 else {
            return 150
        }

        return min(220, max(110, 190 * CGFloat(height) / CGFloat(width)))
    }

    private func relativeDate(_ raw: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var date = iso.date(from: raw)
        if date == nil {
            date = ISO8601DateFormatter().date(from: raw)
        }

        guard let date else { return "" }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
