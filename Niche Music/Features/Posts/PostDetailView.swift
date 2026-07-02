//
//  PostDetailView.swift
//  Niche Music
//
//  Created by Ryan Rahman on 6/2/26.
//


import SwiftUI

struct PostDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var postsStore: PostsStore
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var musicPlayer: MusicPlayer
    @EnvironmentObject private var appNavigation: AppNavigationRouter

    let postId: String
    let initialPost: Post?

    @State private var selectedOptionsItem: FeedItem?
    @State private var selectedCommentsItem: FeedItem?
    @State private var interactionList: PostInteractionListItem?
    @State private var showOwnPostLikeAlert = false
    @State private var showOwnPostRepostAlert = false

    init(postId: String, initialPost: Post? = nil) {
        self.postId = postId
        self.initialPost = initialPost
    }

    private var feedItem: FeedItem? {
        postsStore.feedItem(for: postId)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let item = feedItem {
                PostPageView(
                    item: item,
                    isActive: true,
                    onLike: {
                        if postsStore.toggleLike(
                            postId: postId,
                            currentUserId: session.currentUser?.id
                        ) == .ownPost {
                            showOwnPostLikeAlert = true
                        }
                    },
                    onRepost: {
                        if postsStore.toggleRepost(
                            postId: postId,
                            currentUserId: session.currentUser?.id
                        ) == .ownPost {
                            showOwnPostRepostAlert = true
                        }
                    },
                    onLikeLongPress: {
                        interactionList = PostInteractionListItem(postId: item.post.id, kind: .likes)
                    },
                    onRepostLongPress: {
                        interactionList = PostInteractionListItem(postId: item.post.id, kind: .reposts)
                    },
                    onComment: { selectedCommentsItem = item },
                    onLongPress: { selectedOptionsItem = item }
                )
                .ignoresSafeArea()
            } else if postsStore.isLoadingPost(postId) {
                NicheProgress()
            } else {
                VStack(spacing: 14) {
                    Text("Post not found")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)

                    Button("Try again") {
                        Task {
                            await postsStore.loadPost(id: postId)
                            syncPlayback()
                        }
                    }
                    .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            seedCachedPostIfNeeded()
            syncPlayback()
        }
        .task(id: postId) {
            await postsStore.loadPost(id: postId, force: true)
            postsStore.posts.first(where: { $0.id == postId })?.prefetchDetailMedia()
            syncPlayback()
        }
        .onDisappear {
            FeedPlayerCache.shared.stopAll()
            TabBarVisibility.setVisible(true)
        }
        .onChange(of: feedItem?.post.hasMedia) { _, _ in
            syncPlayback()
        }
        .onChange(of: feedItem?.post.hasTrack) { _, _ in
            syncPlayback()
        }
        .sheet(item: $selectedOptionsItem) { item in
            FeedOptionsSheet(item: item) { postId in
                postsStore.removePostLocally(id: postId)
                dismiss()
            }
            .environmentObject(postsStore)
            .environmentObject(profileStore)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedCommentsItem) { item in
            PostCommentsView(
                postId: item.post.id,
                postSubtitle: postCommentsSubtitle(for: item),
                postOwnerId: item.post.ownerId
            )
            .environmentObject(session)
            .environment(\.sheetExternalNavigation, appNavigation.sheetExternalNavigation {
                selectedCommentsItem = nil
            })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $interactionList) { item in
            PostInteractionListView(postId: item.postId, kind: item.kind)
            .environment(\.sheetExternalNavigation, appNavigation.sheetExternalNavigation {
                interactionList = nil
            })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Can't Like Your Own Post", isPresented: $showOwnPostLikeAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can't like your own post.")
        }
        .alert("Can't Repost Your Own Post", isPresented: $showOwnPostRepostAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can't repost your own post.")
        }
        .externalNavigationDestinations()
    }

    private func seedCachedPostIfNeeded() {
        guard let initialPost else { return }
        postsStore.mergePosts([initialPost])
        initialPost.prefetchDetailMedia()
    }

    private func syncPlayback() {
        guard let post = feedItem?.post else {
            FeedPlayerCache.shared.pauseAll()
            return
        }

        FeedPlayerCache.shared.setActivePost(
            postId: post.id,
            media: post.activePostMedia,
            shouldPlay: true,
            musicPlayerActive: musicPlayer.isPlaying
        )
    }

    private func postCommentsSubtitle(for item: FeedItem) -> String {
        item.postCommentsSubtitle
    }
}
