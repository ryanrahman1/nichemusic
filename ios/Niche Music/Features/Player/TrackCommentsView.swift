//
//  TrackCommentsView.swift
//  Niche Music
//

import SwiftUI

struct TrackCommentsView: View {
    var trackId: String?
    var showsHeader: Bool = true
    var onOpenProfile: ((String) -> Void)? = nil

    @EnvironmentObject private var commentsStore: TrackCommentsStore
    @EnvironmentObject private var musicStore: MusicStore
    @EnvironmentObject private var musicPlayer: MusicPlayer
    @EnvironmentObject private var session: SessionStore
    @Environment(\.sheetExternalNavigation) private var sheetExternalNavigation

    @State private var draft = ""
    @State private var replyTarget: TrackComment?
    @State private var repliesRoot: TrackComment?
    @State private var showTrackSearch = false
    @State private var showGiphyPicker = false
    @State private var actionError: String?

    private var resolvedTrack: NicheTrack? {
        if let trackId {
            return musicStore.track(id: trackId)
        }
        return musicPlayer.currentTrack
    }

    private var resolvedTrackId: String? {
        trackId ?? musicPlayer.currentTrack?.id
    }

    private var comments: [TrackComment] {
        guard let resolvedTrackId else { return [] }

        return commentsStore.comments(for: resolvedTrackId)
            .filter { !$0.isHidden || viewerOwnsTrack }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned && !rhs.isPinned
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    private var isLoading: Bool {
        guard let resolvedTrackId else { return false }
        return commentsStore.isLoading(trackId: resolvedTrackId)
    }

    private var errorMessage: String? {
        guard let resolvedTrackId else { return nil }
        return commentsStore.error(trackId: resolvedTrackId)
    }

    private var viewerOwnsTrack: Bool {
        guard let track = resolvedTrack, let viewerId = session.currentUser?.id else { return false }
        return track.owner.id == viewerId
    }

    private var trackOwnerId: String {
        resolvedTrack?.owner.id ?? ""
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showsHeader {
                    header

                    Divider()
                        .overlay(.white.opacity(0.08))
                }

                content

                if let resolvedTrackId {
                    TrackCommentComposerBar(
                        draft: $draft,
                        replyTarget: replyTarget,
                        onCancelReply: { replyTarget = nil },
                        onSendText: sendText,
                        onAttachTrack: { showTrackSearch = true },
                        onAttachGIF: {
                            dismissKeyboard()
                            showGiphyPicker = true
                        },
                        isSending: commentsStore.isSending(trackId: resolvedTrackId)
                    )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { dismissKeyboard() }
            .navigationDestination(item: $repliesRoot) { comment in
                TrackCommentRepliesView(
                    trackId: resolvedTrackId ?? comment.trackId,
                    rootComment: comment,
                    trackOwnerId: trackOwnerId,
                    onOpenProfile: onOpenProfile
                )
                .environmentObject(commentsStore)
                .environmentObject(session)
            }
        }
        .task(id: resolvedTrackId) {
            guard let resolvedTrackId else { return }
            if trackId != nil {
                _ = try? await musicStore.fetchTrackDetail(id: resolvedTrackId)
            }
            await commentsStore.loadTrackComments(trackId: resolvedTrackId)
        }
        .sheet(isPresented: $showTrackSearch) {
            if let resolvedTrackId {
                TrackCommentTrackSearchView(
                    trackId: resolvedTrackId,
                    parentCommentId: replyTarget?.parentCommentId ?? replyTarget?.id,
                    replyToCommentId: replyTarget?.id
                )
                .environmentObject(commentsStore)
                .environment(\.sheetExternalNavigation, sheetExternalNavigation)
            }
        }
        .alert("Couldn't post comment", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .fullScreenCover(isPresented: $showGiphyPicker) {
            GiphyMediaPicker.PickerSheet { result in
                showGiphyPicker = false
                guard let gif = result else { return }
                Task { await sendGifComment(gif) }
            }
            .background(Color.clear)
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Comments")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)

                Text(resolvedTrack?.name ?? "Track")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(comments.count)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.primary.opacity(0.06), in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && comments.isEmpty {
            VStack {
                Spacer()
                NicheProgress()
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let errorMessage, comments.isEmpty {
            VStack(spacing: 8) {
                Spacer()

                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("Couldn't load comments")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)

                Text(errorMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
        } else if comments.isEmpty {
            VStack(spacing: 8) {
                Spacer()

                Image(systemName: "bubble.left")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.6))

                Text("No comments yet")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)

                Text("Start the conversation around this track.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let resolvedTrackId {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(comments) { comment in
                        TrackCommentRowView(
                            comment: comment,
                            trackId: resolvedTrackId,
                            trackOwnerId: trackOwnerId,
                            viewerOwnsTrack: viewerOwnsTrack,
                            onOpenProfile: onOpenProfile,
                            onReply: { replyTarget = comment },
                            onViewReplies: comment.replyCount > 0
                                ? { repliesRoot = comment }
                                : nil
                        )
                        .onAppear {
                            if comment.id == comments.last?.id {
                                Task { await commentsStore.loadMoreTrackComments(trackId: resolvedTrackId) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 18)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func sendText() {
        guard let resolvedTrackId else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        Task {
            do {
                try await commentsStore.sendTextComment(
                    trackId: resolvedTrackId,
                    text: text,
                    parentCommentId: replyTarget?.parentCommentId ?? replyTarget?.id,
                    replyToCommentId: replyTarget?.id
                )
                draft = ""
                replyTarget = nil
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func sendGifComment(_ gif: GiphyPickResult) async {
        guard let resolvedTrackId else { return }

        do {
            try await commentsStore.sendGifComment(
                trackId: resolvedTrackId,
                gif: gif,
                parentCommentId: replyTarget?.parentCommentId ?? replyTarget?.id,
                replyToCommentId: replyTarget?.id
            )
            replyTarget = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
