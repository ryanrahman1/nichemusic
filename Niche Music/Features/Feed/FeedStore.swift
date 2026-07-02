//
//  FeedStore.swift
//  Niche Music
//
//  Created by Ryan Rahman on 6/1/26.
//


import Foundation
import Combine

@MainActor
final class FeedStore: ObservableObject {
    @Published private(set) var items: [FeedItem] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    
    @Published var currentItemIndex: Int = 0


    private var nextCursor: String?
    private var hasMore = true
    private var isFetchingMore = false
    private let api = APIClient.shared

    @Published private(set) var commentsByPostId: [String: [TrackComment]] = [:]
    @Published var commentsLoadingByPostId: [String: Bool] = [:]
    @Published var commentsErrorByPostId: [String: String] = [:]

    private var commentsLoadedAtByPostId: [String: Date] = [:]
    private var inFlightCommentsTasks: [String: Task<[TrackComment], Error>] = [:]
    private let commentsTtl: TimeInterval = 60
    
    
    var currentItem: FeedItem? {
        guard items.indices.contains(currentItemIndex) else { return nil }
        return items[currentItemIndex]
    }

    func setCurrentIndex(_ index: Int) {
        currentItemIndex = index
        Task { await loadMoreIfNeeded(currentItem: items[safe: index]) }
    }

    func loadInitial() async {
        guard items.isEmpty else { return }
        await loadFeed(reset: true)
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        await loadFeed(reset: true, force: true)
        isRefreshing = false
    }

    func loadMoreIfNeeded(currentItem item: FeedItem?) async {
        guard let item else { return }
        guard hasMore, !isLoading, !isFetchingMore else { return }
        guard let cursor = nextCursor, !cursor.isEmpty else { return }

        let thresholdIndex = items.index(items.endIndex, offsetBy: -3, limitedBy: items.startIndex) ?? items.startIndex

        if let currentIndex = items.lastIndex(where: { $0.id == item.id }),
           currentIndex >= thresholdIndex {
            await loadFeed(reset: false)
        }
    }

    func toggleLike(_ item: FeedItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        let wasLiked = items[index].viewer.isLiked

        items[index].viewer.isLiked.toggle()
        items[index].post.likeCount += wasLiked ? -1 : 1

        Task {
            do {
                if wasLiked {
                    try await api.requestVoid(Endpoints.unlikePost(id: item.post.id), method: .post)
                } else {
                    try await api.requestVoid(Endpoints.likePost(id: item.post.id), method: .post)
                }
            } catch {
                await MainActor.run {
                    if let rollbackIndex = items.firstIndex(where: { $0.id == item.id }) {
                        items[rollbackIndex].viewer.isLiked = wasLiked
                        items[rollbackIndex].post.likeCount += wasLiked ? 1 : -1
                    }
                }
            }
        }
    }

    func comments(for postId: String) -> [TrackComment] {
        commentsByPostId[postId] ?? []
    }

    func loadPostComments(postId: String, force: Bool = false) async {
        do {
            _ = try await fetchPostComments(postId: postId, force: force)
        } catch {
            commentsErrorByPostId[postId] = error.localizedDescription
        }
    }

    @discardableResult
    func fetchPostComments(postId: String, force: Bool = false) async throws -> [TrackComment] {
        if !force,
           let cached = commentsByPostId[postId],
           let loadedAt = commentsLoadedAtByPostId[postId],
           Date().timeIntervalSince(loadedAt) < commentsTtl {
            return cached
        }

        if let task = inFlightCommentsTasks[postId] {
            return try await task.value
        }

        commentsLoadingByPostId[postId] = true
        commentsErrorByPostId[postId] = nil

        let task = Task<[TrackComment], Error> {
            let response: TrackCommentsResponse = try await api.request(
                Endpoints.getPostComments(id: postId),
                method: .get
            )
            return response.comments
        }

        inFlightCommentsTasks[postId] = task

        do {
            let comments = try await task.value
            commentsByPostId[postId] = comments
            commentsLoadedAtByPostId[postId] = Date()
            commentsLoadingByPostId[postId] = false
            inFlightCommentsTasks[postId] = nil
            return comments
        } catch {
            commentsLoadingByPostId[postId] = false
            inFlightCommentsTasks[postId] = nil
            throw error
        }
    }

    func removePost(id: String) {
        items.removeAll { $0.id == id }
        if currentItemIndex >= items.count {
            currentItemIndex = max(0, items.count - 1)
        }
    }

    func toggleRepost(_ item: FeedItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        let wasReposted = items[index].viewer.isReposted

        items[index].viewer.isReposted.toggle()
        items[index].post.repostCount += wasReposted ? -1 : 1

        Task {
            do {
                if wasReposted {
                    try await api.requestVoid(Endpoints.unrepostPost(id: item.post.id), method: .post)
                } else {
                    try await api.requestVoid(Endpoints.repostPost(id: item.post.id), method: .post)
                }
            } catch {
                await MainActor.run {
                    if let rollbackIndex = items.firstIndex(where: { $0.id == item.id }) {
                        items[rollbackIndex].viewer.isReposted = wasReposted
                        items[rollbackIndex].post.repostCount += wasReposted ? 1 : -1
                    }
                }
            }
        }
    }

    private func loadFeed(reset: Bool, force: Bool = false) async {
        if reset {
            guard force || !isLoading else { return }
        } else {
            guard !isFetchingMore, let cursor = nextCursor, !cursor.isEmpty else { return }
            guard hasMore else { return }
        }

        if reset {
            isLoading = true
        } else {
            isFetchingMore = true
        }
        errorMessage = nil
        defer {
            if reset {
                isLoading = false
            } else {
                isFetchingMore = false
            }
        }

        do {
            var query: [String: String?] = [
                "limit": "8"
            ]

            if reset {
                nextCursor = nil
                hasMore = true
            } else {
                query["cursor"] = nextCursor
            }

            let response: (result: FeedResult, metadata: APIMetadata?) = try await api.requestWithMetadata(
                Endpoints.feedHome,
                method: .get,
                query: query
            )

            let pagination = response.metadata?.pagination

            let previousCursor = nextCursor

            if reset {
                items = response.result.items
            } else {
                let existingIds = Set(items.map(\.id))
                let newItems = response.result.items.filter { !existingIds.contains($0.id) }
                if newItems.isEmpty {
                    let updatedCursor = pagination?.nextCursor
                    // Stop pagination loops when the API keeps returning the same page/cursor.
                    if updatedCursor == previousCursor || updatedCursor == nil {
                        hasMore = false
                    } else {
                        nextCursor = updatedCursor
                        hasMore = pagination?.hasMore ?? false
                    }
                    return
                }
                items.append(contentsOf: newItems)
            }

            nextCursor = pagination?.nextCursor
            hasMore = pagination?.hasMore ?? false

            if !reset, nextCursor == previousCursor {
                hasMore = false
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch let error as APIClientError {
            if case .network(let underlying) = error,
               let urlError = underlying as? URLError,
               urlError.code == .cancelled {
                return
            }
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}


private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
