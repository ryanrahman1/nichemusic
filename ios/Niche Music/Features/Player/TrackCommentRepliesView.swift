//
//  TrackCommentRepliesView.swift
//  Niche Music
//

import SwiftUI

struct TrackCommentRepliesView: View {
    @EnvironmentObject private var commentsStore: TrackCommentsStore
    @EnvironmentObject private var session: SessionStore
    @Environment(\.sheetExternalNavigation) private var sheetExternalNavigation

    let trackId: String
    let rootComment: TrackComment
    let trackOwnerId: String
    var onOpenProfile: ((String) -> Void)? = nil

    @State private var replyTarget: TrackComment?
    @State private var draft = ""
    @State private var showTrackSearch = false
    @State private var showGiphyPicker = false
    @State private var actionError: String?

    private var replies: [TrackComment] {
        commentsStore.replies(for: rootComment.id)
    }

    private var viewerOwnsTrack: Bool {
        session.currentUser?.id == trackOwnerId
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                repliesList
            }

            TrackCommentComposerBar(
                draft: $draft,
                replyTarget: replyTarget,
                onCancelReply: { replyTarget = nil },
                onSendText: sendText,
                onAttachTrack: { showTrackSearch = true },
                onAttachGIF: { showGiphyPicker = true },
                isSending: commentsStore.isSending(trackId: trackId)
            )
        }
        .navigationTitle("Replies")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await commentsStore.loadReplies(trackId: trackId, commentId: rootComment.id)
        }
        .sheet(isPresented: $showTrackSearch) {
            TrackCommentTrackSearchView(
                trackId: trackId,
                parentCommentId: rootComment.id,
                replyToCommentId: replyTarget?.id ?? rootComment.id
            )
            .environmentObject(commentsStore)
            .environment(\.sheetExternalNavigation, sheetExternalNavigation)
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

    private var repliesList: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            TrackCommentRowView(
                comment: rootComment,
                trackId: trackId,
                trackOwnerId: trackOwnerId,
                viewerOwnsTrack: viewerOwnsTrack,
                onOpenProfile: onOpenProfile,
                onReply: { replyTarget = rootComment },
                onViewReplies: nil
            )

            Divider()

            ForEach(replies) { reply in
                TrackCommentReplyRow(
                    reply: reply,
                    trackId: trackId,
                    trackOwnerId: trackOwnerId,
                    viewerOwnsTrack: viewerOwnsTrack,
                    parentCommentId: rootComment.id,
                    isLastReply: reply.id == replies.last?.id,
                    onOpenProfile: onOpenProfile,
                    onReply: { replyTarget = reply },
                    onLoadMore: loadMoreReplies
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func loadMoreReplies() {
        Task {
            await commentsStore.loadMoreReplies(
                trackId: trackId,
                commentId: rootComment.id
            )
        }
    }

    private func sendText() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        Task {
            do {
                try await commentsStore.sendTextComment(
                    trackId: trackId,
                    text: text,
                    parentCommentId: rootComment.id,
                    replyToCommentId: replyTarget?.id ?? rootComment.id
                )
                draft = ""
                replyTarget = nil
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func sendGifComment(_ gif: GiphyPickResult) async {
        do {
            try await commentsStore.sendGifComment(
                trackId: trackId,
                gif: gif,
                parentCommentId: rootComment.id,
                replyToCommentId: replyTarget?.id ?? rootComment.id
            )
            replyTarget = nil
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private struct TrackCommentReplyRow: View {
    let reply: TrackComment
    let trackId: String
    let trackOwnerId: String
    let viewerOwnsTrack: Bool
    let parentCommentId: String
    let isLastReply: Bool
    var onOpenProfile: ((String) -> Void)?
    let onReply: () -> Void
    let onLoadMore: () -> Void

    var body: some View {
        TrackCommentRowView(
            comment: reply,
            trackId: trackId,
            trackOwnerId: trackOwnerId,
            viewerOwnsTrack: viewerOwnsTrack,
            parentCommentId: parentCommentId,
            onOpenProfile: onOpenProfile,
            onReply: onReply,
            onViewReplies: nil
        )
        .onAppear {
            guard isLastReply else { return }
            onLoadMore()
        }
    }
}
