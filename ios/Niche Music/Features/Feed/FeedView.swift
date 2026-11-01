//
//  FeedView.swift
//  Niche Music
//
//  Created by Ryan Rahman on 6/1/26.
//
import SwiftUI
import Kingfisher
import GoogleMobileAds

enum FeedRenderableItem: Identifiable {
    case post(index: Int, item: FeedItem)
    case ad(id: String, ad: NativeAd)

    var id: String {
        switch self {
        case .post(_, let item):
            return "post-\(item.id)"
        case .ad(let id, _):
            return "ad-\(id)"
        }
    }
}

struct FeedView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var musicPlayer: MusicPlayer
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var appNavigation: AppNavigationRouter
    @EnvironmentObject private var postsStore: PostsStore
    @EnvironmentObject private var profileStore: ProfileStore
    @StateObject private var store = FeedStore()
    
    @StateObject private var nativeAdLoader = NativeAdLoader()

    /// True when the Home tab is selected.
    var isVisible: Bool = true

    @State private var activeIndex: Int?
    @State private var showCreatePostFlow = false
    @State private var pendingPostIdAfterCreate: String?
    @State private var createdPostRoute: PostDetailNavigationRoute?
    @State private var selectedOptionsItem: FeedItem?
    @State private var selectedCommentsItem: FeedItem?
    @State private var interactionList: PostInteractionListItem?

    private let visibilityThreshold: CGFloat = 0.5

    private func postCommentsSubtitle(for item: FeedItem) -> String {
        item.postCommentsSubtitle
    }

    var body: some View {
        NavigationStack {
            feedContent
                .externalNavigationDestinations()
                .navigationDestination(item: $createdPostRoute) { route in
                    PostDetailView(postId: route.postId)
                }
        }
    }

    private var feedContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if store.items.isEmpty && store.isLoading {
                NicheProgress()
            } else if let error = store.errorMessage, store.items.isEmpty {
                errorView(error)
            } else {
                feedScroll
            }

            topBar
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await store.loadInitial()
            maintainAdInventory()
        }
        .onAppear {
            if isVisible {
                syncActivePostPlayback()
            }
        }
        .onChange(of: store.items.count) { _, _ in
            syncActivePostPlayback()
            maintainAdInventory()
        }
        .onChange(of: isVisible) { _, visible in
            if visible {
                syncActivePostPlayback()
                trackImpressionForActivePost()
            } else {
                FeedPlayerCache.shared.stopAll()
                FeedEventLogger.shared.cancelPendingImpression()
            }
        }
        .onChange(of: musicPlayer.isPlaying) { _, _ in
            syncActivePostPlayback()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, isVisible {
                FeedPlayerCache.shared.clearAppBackgroundSuspension()
                syncActivePostPlayback()
            }
        }
        .onDisappear {
            FeedPlayerCache.shared.stopAll()
            FeedEventLogger.shared.cancelPendingImpression()
        }
        .onChange(of: showCreatePostFlow) { wasOpen, isOpen in
            if isOpen {
                musicPlayer.pauseAllPlayback()
                FeedPlayerCache.shared.stopAll()
            } else {
                if wasOpen {
                    navigateToCreatedPostIfNeeded()
                }
                if isVisible {
                    syncActivePostPlayback()
                }
            }
        }
        .fullScreenCover(isPresented: $showCreatePostFlow) {
            CreatePostFlowView { postId in
                pendingPostIdAfterCreate = postId
                showCreatePostFlow = false
            }
            .environmentObject(postsStore)
            .environmentObject(session)
            .environmentObject(musicPlayer)
            .environmentObject(appNavigation)
        }
        .sheet(item: $selectedOptionsItem) { item in
            FeedOptionsSheet(item: item) { postId in
                store.removePost(id: postId)
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
    }
    
    private var renderedItems: [FeedRenderableItem] {
        var output: [FeedRenderableItem] = []
        var adIndex = 0

        for (index, item) in store.items.enumerated() {
            output.append(.post(index: index, item: item))

            let shouldInsertAd = index > 0 && index % 7 == 0

            if shouldInsertAd, nativeAdLoader.ads.indices.contains(adIndex) {
                output.append(.ad(
                    id: "\(adIndex)-after-\(item.id)",
                    ad: nativeAdLoader.ads[adIndex]
                ))
                adIndex += 1
            }
        }

        return output
    }
    
    private func maintainAdInventory() {
        let requiredAds = max(8, store.items.count / 8 + 2)
        nativeAdLoader.maintainInventory(requiredAds: requiredAds)
    }

    private var feedScroll: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(renderedItems.enumerated()), id: \.element.id) { renderIndex, renderItem in
                        switch renderItem {
                        case .post(let index, let item):
                            FeedPostPageView(
                                item: item,
                                isActive: activeIndex == index,
                                onLike: { store.toggleLike(item) },
                                onRepost: { store.toggleRepost(item) },
                                onLikeLongPress: {
                                    interactionList = PostInteractionListItem(postId: item.post.id, kind: .likes)
                                },
                                onRepostLongPress: {
                                    interactionList = PostInteractionListItem(postId: item.post.id, kind: .reposts)
                                },
                                onComment: { selectedCommentsItem = item },
                                onLongPress: { selectedOptionsItem = item }
                            )
                            .frame(width: geo.size.width, height: geo.size.height)
                            .feedPostVisibility(index: index)
                            .onAppear {
                                prefetchAround(index: index)
                                Task { await store.loadMoreIfNeeded(currentItem: item) }
                            }

                        case .ad(_, let ad):
                            FeedNativeAdPageView(nativeAd: ad)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .ignoresSafeArea()
                                .onAppear {
                                    FeedPlayerCache.shared.pauseAll()
                                    nativeAdLoader.ensureInventory()
                                }
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .refreshable {
                await refreshFeed()
            }
            .onPreferenceChange(FeedVisibilityPreferenceKey.self) { visibilities in
                updateActiveIndex(from: visibilities, viewport: geo.frame(in: .global))
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    private func refreshFeed() async {
        // `.refreshable` cancels its task when the pull gesture ends, which would
        // abort the network request. Run refresh in an unstructured task instead.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task { @MainActor in
                defer { continuation.resume() }
                FeedEventLogger.shared.cancelPendingImpression()
                await store.refresh()
                activeIndex = store.items.isEmpty ? nil : 0
                maintainAdInventory()
                syncActivePostPlayback()
                trackImpressionForActivePost()
            }
        }
    }

    private func updateActiveIndex(from visibilities: [FeedPostVisibility], viewport: CGRect) {
        guard isVisible, viewport.height > 0 else {
            FeedEventLogger.shared.cancelPendingImpression()
            return
        }

        let nextIndex = FeedVisibility.activeIndex(
            in: visibilities,
            viewportFrame: viewport,
            threshold: visibilityThreshold
        )

        guard nextIndex != activeIndex else { return }

        activeIndex = nextIndex
        trackImpressionForActivePost()

        if nextIndex != nil {
            FeedPlayerCache.shared.resetPreviewPauseState()
        }

        syncActivePostPlayback()
    }

    private func trackImpressionForActivePost() {
        guard isVisible,
              let activeIndex,
              store.items.indices.contains(activeIndex) else {
            FeedEventLogger.shared.cancelPendingImpression()
            return
        }

        FeedEventLogger.shared.scheduleImpression(postId: store.items[activeIndex].post.id)
    }

    private func navigateToCreatedPostIfNeeded() {
        guard let postId = pendingPostIdAfterCreate else { return }
        pendingPostIdAfterCreate = nil

        Task { @MainActor in
            // Wait for the full-screen cover dismiss animation to finish before pushing.
            try? await Task.sleep(nanoseconds: 500_000_000)
            await postsStore.loadPost(id: postId, force: true)
            postsStore.posts.first(where: { $0.id == postId })?.prefetchDetailMedia()
            createdPostRoute = PostDetailNavigationRoute(postId: postId)
            await store.refresh()
        }
    }

    private func syncActivePostPlayback() {
        guard isVisible, !showCreatePostFlow else {
            FeedPlayerCache.shared.pauseAll()
            return
        }

        guard let activeIndex,
              store.items.indices.contains(activeIndex) else {
            FeedPlayerCache.shared.pauseAll()
            return
        }

        let post = store.items[activeIndex].post

        FeedPlayerCache.shared.setActivePost(
            postId: post.id,
            media: post.activePostMedia,
            shouldPlay: true,
            musicPlayerActive: musicPlayer.isPlaying
        )
    }

    private func prefetchAround(index: Int) {
        let prefetchRange = (index - 1)...(index + 3)
        for i in prefetchRange where store.items.indices.contains(i) {
            let item = store.items[i]
            FeedPlayerCache.shared.prefetch(media: item.post.activePostMedia)

            if let imageURL = item.post.primaryDisplayImageURL {
                KingfisherManager.shared.retrieveImage(with: imageURL) { _ in }
            }
            if let avatarUrl = item.post.owner.avatarUrl,
               let url = URL(string: avatarUrl) {
                KingfisherManager.shared.retrieveImage(with: url) { _ in }
            }
        }
    }

    private var topBar: some View {
        VStack {
            HStack {
                Image("favicon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .blendMode(.difference)

                Spacer()

                Button {
                    showCreatePostFlow = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, -8)
                .padding(.top, -4)
                .padding(.bottom, -4)
                .padding(.leading, -4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()
        }
    }

    @ViewBuilder
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Text("Couldn't load feed")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            Text(error)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await store.refresh() }
            }
            .foregroundStyle(.white)
        }
        .padding()
    }
}
