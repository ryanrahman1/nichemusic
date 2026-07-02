//
//  PostCommentsView.swift
//  Niche Music
//

import SwiftUI

struct PostCommentsView: View {
    @EnvironmentObject private var commentsStore: PostCommentsStore
    @EnvironmentObject private var session: SessionStore
    @Environment(\.sheetExternalNavigation) private var sheetExternalNavigation

    let postId: String
    let postSubtitle: String
    let postOwnerId: String

    @State private var draft = ""
    @State private var replyTarget: TrackComment?
    @State private var repliesRoot: TrackComment?
    @State private var showTrackSearch = false
    @State private var showGiphyPicker = false
    @State private var actionError: String?

    private var comments: [TrackComment] {
        commentsStore.comments(for: postId)
            .filter { !$0.isHidden || viewerOwnsPost }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned && !rhs.isPinned
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    private var isLoading: Bool {
        commentsStore.isLoading(postId: postId)
    }

    private var errorMessage: String? {
        commentsStore.error(postId: postId)
    }

    private var viewerOwnsPost: Bool {
        session.currentUser?.id == postOwnerId
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                Divider()
                    .overlay(.primary.opacity(0.08))

                content

                PostCommentComposerBar(
                    postId: postId,
                    draft: $draft,
                    replyTarget: replyTarget,
                    onCancelReply: { replyTarget = nil },
                    onSendText: sendText,
                    onAttachTrack: { showTrackSearch = true },
                    onAttachGIF: {
                        dismissKeyboard()
                        showGiphyPicker = true
                    },
                    isSending: commentsStore.isSending(postId: postId)
                )
            }
            .contentShape(Rectangle())
            .onTapGesture { dismissKeyboard() }
            .navigationDestination(item: $repliesRoot) { comment in
                PostCommentRepliesView(
                    postId: postId,
                    rootComment: comment,
                    postOwnerId: postOwnerId
                )
                .environmentObject(commentsStore)
                .environmentObject(session)
            }
        }
        .task(id: postId) {
            await commentsStore.loadPostComments(postId: postId)
        }
        .sheet(isPresented: $showTrackSearch) {
            PostCommentTrackSearchView(
                postId: postId,
                parentCommentId: replyTarget?.parentCommentId ?? replyTarget?.id,
                replyToCommentId: replyTarget?.id
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

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Comments")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)

                Text(postSubtitle)
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
                Text("Start the conversation around this post.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(comments) { comment in
                        PostCommentRowView(
                            comment: comment,
                            postId: postId,
                            postOwnerId: postOwnerId,
                            viewerOwnsPost: viewerOwnsPost,
                            onReply: { replyTarget = comment },
                            onViewReplies: comment.replyCount > 0
                                ? { repliesRoot = comment }
                                : nil
                        )
                        .onAppear {
                            if comment.id == comments.last?.id {
                                Task { await commentsStore.loadMorePostComments(postId: postId) }
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
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        Task {
            do {
                try await commentsStore.sendTextComment(
                    postId: postId,
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
        do {
            try await commentsStore.sendGifComment(
                postId: postId,
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
