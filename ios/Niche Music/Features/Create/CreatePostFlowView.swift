//
//  CreatePostFlowView.swift
//  Niche Music
//

import SwiftUI

private enum CreatePostRoute: Hashable {
    case compose
}

struct CreatePostFlowView: View {
    /// Called when the flow should end. Pass a post id after a successful publish, or nil when cancelled.
    let onComplete: (String?) -> Void

    @EnvironmentObject private var postsStore: PostsStore
    @EnvironmentObject private var musicPlayer: MusicPlayer

    @StateObject private var store = CreatePostStore()
    @StateObject private var draftStore = PostDraftStore()

    @State private var path: [CreatePostRoute] = []
    @State private var isPublishing = false
    @State private var publishErrorMessage: String?

    init(onComplete: @escaping (String?) -> Void) {
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            NavigationStack(path: $path) {
                CreatePostCameraView(
                    store: store,
                    draftStore: draftStore,
                    onNext: { path.append(.compose) },
                    onClose: { finish(postId: nil) }
                )
                .navigationDestination(for: CreatePostRoute.self) { route in
                    switch route {
                    case .compose:
                        CreatePostComposeView(
                            store: store,
                            draftStore: draftStore,
                            onPublish: {
                                Task { await publishPost() }
                            }
                        )
                    }
                }
            }

            if isPublishing {
                CreatePostPublishingView(
                    progress: store.uploadProgress,
                    stage: store.publishStage
                )
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isPublishing)
        .alert("Couldn't post", isPresented: Binding(
            get: { publishErrorMessage != nil },
            set: { if !$0 { publishErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(publishErrorMessage ?? "")
        }
        .onAppear {
            pauseAllAppAudio()
        }
        .onChange(of: path.count) { oldCount, newCount in
            if newCount < oldCount {
                store.clearMedia()
            }
        }
    }

    private func pauseAllAppAudio() {
        musicPlayer.pauseAllPlayback()
        FeedPlayerCache.shared.stopAll()
    }

    @MainActor
    private func finish(postId: String?) {
        isPublishing = false
        onComplete(postId)
    }

    @MainActor
    private func publishPost() async {
        isPublishing = true
        publishErrorMessage = nil

        if let postId = await store.publish(draftStore: draftStore, postsStore: postsStore) {
            try? await Task.sleep(nanoseconds: 450_000_000)
            finish(postId: postId)
        } else {
            isPublishing = false
            if case .failed(let message) = store.publishStage {
                publishErrorMessage = message
            }
        }
    }
}
