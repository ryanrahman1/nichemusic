//
//  FeedHelpers.swift
//  Niche Music
//
//  Created by Ryan Rahman on 6/1/26.
//

import SwiftUI
import AVKit

struct CreateFeedSheet: View {
    var onCreatePost: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Create")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.white)

            VStack(spacing: 0) {
                createRow("Post", "Share a moment or music thought.", "square.and.pencil", action: onCreatePost)
                createRow("Upload Track", "Release music directly on Niche.", "music.note")
                createRow("Create Group", "Start a space around a scene or sound.", "person.3")
            }

            Spacer()
        }
        .padding(24)
    }

    private func createRow(_ title: String, _ subtitle: String, _ icon: String, action: (() -> Void)? = nil) -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.48))
                }

                Spacer()
            }
            .padding(.vertical, 18)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(height: 1)
        }
    }
}

struct FeedOptionsSheet: View {
    let item: FeedItem
    var onPostDeleted: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var postsStore: PostsStore
    @EnvironmentObject private var profileStore: ProfileStore

    @State private var showReport = false
    @State private var showEditPost = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var actionError: String?

    private var isOwner: Bool {
        postsStore.isOwner(postId: item.post.id, currentUserId: session.currentUser?.id)
            || session.currentUser?.id == item.post.ownerId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Post options")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)

            Text("@\(item.post.owner.username)")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))

            VStack(spacing: 0) {
                if isOwner {
                    optionRow("Edit post", "pencil") {
                        Task {
                            await postsStore.loadPost(id: item.post.id, force: true)
                            showEditPost = true
                        }
                    }
                    optionRow("Delete post", "trash", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }

                optionRow("Share", "square.and.arrow.up") {}
                if !isOwner {
                    optionRow("Report", "flag") {
                        showReport = true
                    }
                }
                optionRow("Not interested", "minus.circle") {}
            }

            Spacer()
        }
        .padding(24)
        .sheet(isPresented: $showEditPost) {
            NavigationStack {
                if let post = postsStore.posts.first(where: { $0.id == item.post.id }) {
                    EditPostView(post: post)
                        .environmentObject(postsStore)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showReport) {
            NavigationStack {
                FeedbackFormView(
                    title: "Report Post",
                    placeholder: "Describe what's wrong with this post…",
                    buttonLabel: "Submit Report"
                ) { text in
                    try await ReportsService.submit(
                        targetType: .post,
                        targetId: item.post.id,
                        message: text,
                        reportedUserId: item.post.ownerId,
                        content: ["source": "feed"]
                    )
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Delete this post?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Post", role: .destructive) {
                Task { await deletePost() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .alert("Couldn't delete post", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .overlay {
            if isDeleting {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    NicheProgress()
                }
            }
        }
    }

    private func deletePost() async {
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await postsStore.deletePost(id: item.post.id, profileStore: profileStore)
            onPostDeleted?(item.post.id)
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func optionRow(
        _ title: String,
        _ icon: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 26)

                Text(title)
                    .font(.system(size: 17, weight: .medium))

                Spacer()
            }
            .foregroundStyle(role == .destructive ? .red : .white)
            .padding(.vertical, 18)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(height: 1)
        }
    }
}
