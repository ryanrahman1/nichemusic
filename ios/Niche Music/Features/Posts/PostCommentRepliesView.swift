//
//  PostCommentRepliesView.swift
//  Niche Music
//

import SwiftUI

struct PostCommentRepliesView: View {
    @EnvironmentObject private var commentsStore: PostCommentsStore
    @EnvironmentObject private var session: SessionStore
    @Environment(\.sheetExternalNavigation) private var sheetExternalNavigation

    let postId: String
    let rootComment: TrackComment
    let postOwnerId: String

    @State private var replyTarget: TrackComment?
    @State private var draft = ""
    @State private var showTrackSearch = false
    @State private var showGiphyPicker = false
    @State private var actionError: String?

    private var replies: [TrackComment] {
        commentsStore.replies(for: rootComment.id)
    }

    private var viewerOwnsPost: Bool {
        session.currentUser?.id == postOwnerId
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                repliesList
            }

            PostCommentComposerBar(
                postId: postId,
                draft: $draft,
                replyTarget: replyTarget,
                onCancelReply: { replyTarget = nil },
                onSendText: sendText,
                onAttachTrack: { showTrackSearch = true },
                onAttachGIF: {
                    showGiphyPicker = true
                },
                isSending: commentsStore.isSending(postId: postId)
            )
        }
        .navigationTitle("Replies")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await commentsStore.loadReplies(postId: postId, commentId: rootComment.id)
        }
        .sheet(isPresented: $showTrackSearch) {
            PostCommentTrackSearchView(
                postId: postId,
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
            PostCommentRowView(
                comment: rootComment,
                postId: postId,
                postOwnerId: postOwnerId,
                viewerOwnsPost: viewerOwnsPost,
                onReply: { replyTarget = rootComment },
                onViewReplies: nil
            )

            Divider()

            ForEach(replies) { reply in
                PostCommentReplyRow(
                    reply: reply,
                    postId: postId,
                    postOwnerId: postOwnerId,
                    viewerOwnsPost: viewerOwnsPost,
                    parentCommentId: rootComment.id,
                    isLastReply: reply.id == replies.last?.id,
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
                postId: postId,
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
                    postId: postId,
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
                postId: postId,
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

private struct PostCommentReplyRow: View {
    let reply: TrackComment
    let postId: String
    let postOwnerId: String
    let viewerOwnsPost: Bool
    let parentCommentId: String
    let isLastReply: Bool
    let onReply: () -> Void
    let onLoadMore: () -> Void

    var body: some View {
        PostCommentRowView(
            comment: reply,
            postId: postId,
            postOwnerId: postOwnerId,
            viewerOwnsPost: viewerOwnsPost,
            parentCommentId: parentCommentId,
            onReply: onReply,
            onViewReplies: nil
        )
        .onAppear {
            guard isLastReply else { return }
            onLoadMore()
        }
    }
}
