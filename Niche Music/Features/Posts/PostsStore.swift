//
//  PostsStore.swift
//  Niche Music
//
//  Created by Ryan Rahman on 6/1/26.
//

import Foundation
import Combine

struct PostsResult: Decodable {
    let posts: [Post]
}

struct PostDetailResponse: Decodable {
    let post: Post
    let viewer: PostViewerDetail
}

struct PostViewerDetail: Decodable {
    let isOwner: Bool
    let isLiked: Bool
    let isReposted: Bool
}

enum PostInteractionBlockReason {
    case ownPost
}

struct PostOwner: Decodable, Equatable {
    let id: String
    let username: String
    let avatarUrl: String?
    let profileType: String?
    let typeUpdatedAt: String?
}

struct PostGroup: Decodable, Equatable {
    let id: String
    let name: String
}

struct Post: Decodable, Identifiable, Equatable {
    let id: String
    let ownerId: String
    let groupId: String?
    let kind: PostKind
    let trackId: String?
    let nicheTrackId: String?
    let visibility: PostVisibility

    var likeCount: Int
    var repostCount: Int
    let commentCount: Int
    let viewCount: Int
    let shareCount: Int

    let createdAt: String
    let updatedAt: String?

    let content: PostContent
    let hasMedia: Bool
    let hasTrack: Bool
    let hasSound: Bool

    let owner: PostOwner
    let group: PostGroup?
    let track: PostTrack?
    let nicheTrack: PostNicheTrack?
}

extension Post {
    var resolvedNicheTrack: PostNicheTrack? {
        nicheTrack ?? content.nicheTrack
    }

    var thumbnailURL: URL? {
        if let mediaURL = content.media?.first?.url {
            return URL(string: mediaURL)
        }

        if let artwork = resolvedNicheTrack?.resolvedArtworkURL {
            return artwork
        }

        if let artwork = (track ?? content.track)?.artworkUrl {
            let resolved = artwork
                .replacingOccurrences(of: "{w}", with: "500")
                .replacingOccurrences(of: "{h}", with: "500")
            return URL(string: resolved)
        }

        return nil
    }

    var isVideo: Bool {
        content.media?.first?.kind == "video"
    }

    var isPMO: Bool {
        kind == .pmo || content.template?.name == "pmo"
    }

    var showsMusicBadge: Bool {
        isPMO || kind == .track || resolvedNicheTrack != nil || track != nil || content.track != nil
    }
}

@MainActor
final class PostsStore: ObservableObject {
    @Published private(set) var posts: [Post] = []
    @Published private(set) var viewerByPostId: [String: FeedViewer] = [:]
    @Published private(set) var ownerByPostId: [String: Bool] = [:]
    @Published private(set) var loadingPostIds: Set<String> = []
    @Published var errorMessage: String?

    var isLoading: Bool { !loadingPostIds.isEmpty }

    func isLoadingPost(_ id: String) -> Bool {
        loadingPostIds.contains(id)
    }

    private let api = APIClient.shared

    func mergePosts(_ incoming: [Post]) {
        for post in incoming {
            if let index = posts.firstIndex(where: { $0.id == post.id }) {
                posts[index] = preferRicherPost(existing: posts[index], incoming: post)
            } else {
                posts.append(post)
            }
        }
    }

    private func preferRicherPost(existing: Post, incoming: Post) -> Post {
        let existingScore = richnessScore(for: existing)
        let incomingScore = richnessScore(for: incoming)

        if incomingScore >= existingScore {
            return incoming
        }

        var kept = existing
        kept.likeCount = incoming.likeCount
        kept.repostCount = incoming.repostCount
        return kept
    }

    private func richnessScore(for post: Post) -> Int {
        var score = 0
        score += (post.content.media?.count ?? 0) * 10
        if post.resolvedNicheTrack?.musicUrl != nil { score += 8 }
        if post.resolvedNicheTrack?.momentUrl != nil { score += 2 }
        if post.track != nil || post.content.track != nil { score += 6 }
        if post.nicheTrack != nil { score += 4 }
        if post.hasMedia { score += 3 }
        if post.hasTrack { score += 3 }
        return score
    }
    
    func loadPost(id: String, force: Bool = false) async {
        if !force, posts.contains(where: { $0.id == id }) {
            let cached = posts.first(where: { $0.id == id })!
            if richnessScore(for: cached) > 0 {
                return
            }
        }

        let isCached = posts.contains(where: { $0.id == id })
        if !isCached {
            loadingPostIds.insert(id)
        }

        defer {
            if !isCached {
                loadingPostIds.remove(id)
            }
        }

        errorMessage = nil

        do {
            let response: PostDetailResponse = try await api.request(
                Endpoints.post(id: id),
                method: .get
            )

            mergePosts([response.post])
            viewerByPostId[response.post.id] = FeedViewer(
                isLiked: response.viewer.isLiked,
                isReposted: response.viewer.isReposted
            )
            ownerByPostId[response.post.id] = response.viewer.isOwner
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func isOwner(postId: String, currentUserId: String?) -> Bool {
        if let cached = ownerByPostId[postId] {
            return cached
        }
        guard let currentUserId,
              let post = posts.first(where: { $0.id == postId }) else {
            return false
        }
        return post.ownerId == currentUserId
    }

    func updatePost(id: String, body: UpdatePostBody) async throws -> Post {
        let response: UpdatePostResponse = try await api.request(
            Endpoints.updatePost(id: id),
            method: .post,
            body: body
        )
        mergePosts([response.post])
        ownerByPostId[response.post.id] = response.viewer.isOwner
        return response.post
    }

    func deletePost(id: String, profileStore: ProfileStore) async throws {
        try await api.requestVoid(
            Endpoints.deletePost(id: id),
            method: .post
        )

        posts.removeAll { $0.id == id }
        viewerByPostId.removeValue(forKey: id)
        ownerByPostId.removeValue(forKey: id)
        profileStore.removePostFromCaches(postId: id)
    }

    func removePostLocally(id: String) {
        posts.removeAll { $0.id == id }
        viewerByPostId.removeValue(forKey: id)
        ownerByPostId.removeValue(forKey: id)
    }

    func feedItem(for postId: String) -> FeedItem? {
        guard let post = posts.first(where: { $0.id == postId }) else {
            return nil
        }

        var item = post.asFeedItem
        if let viewer = viewerByPostId[postId] {
            item.viewer = viewer
        }
        return item
    }

    @discardableResult
    func toggleLike(postId: String, currentUserId: String?) -> PostInteractionBlockReason? {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else { return nil }

        let post = posts[index]
        if post.ownerId == currentUserId {
            return .ownPost
        }

        var viewer = viewerByPostId[postId] ?? FeedViewer(isLiked: false, isReposted: false)
        let wasLiked = viewer.isLiked

        viewer.isLiked.toggle()
        viewerByPostId[postId] = viewer
        posts[index].likeCount += wasLiked ? -1 : 1

        Task {
            do {
                if wasLiked {
                    try await api.requestVoid(Endpoints.unlikePost(id: postId), method: .post)
                } else {
                    try await api.requestVoid(Endpoints.likePost(id: postId), method: .post)
                }
            } catch {
                await MainActor.run {
                    guard let rollbackIndex = posts.firstIndex(where: { $0.id == postId }) else { return }
                    var rollbackViewer = viewerByPostId[postId] ?? FeedViewer(isLiked: false, isReposted: false)
                    rollbackViewer.isLiked = wasLiked
                    viewerByPostId[postId] = rollbackViewer
                    posts[rollbackIndex].likeCount += wasLiked ? 1 : -1
                }
            }
        }

        return nil
    }

    @discardableResult
    func toggleRepost(postId: String, currentUserId: String?) -> PostInteractionBlockReason? {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else { return nil }

        let post = posts[index]
        if post.ownerId == currentUserId {
            return .ownPost
        }

        var viewer = viewerByPostId[postId] ?? FeedViewer(isLiked: false, isReposted: false)
        let wasReposted = viewer.isReposted

        viewer.isReposted.toggle()
        viewerByPostId[postId] = viewer
        posts[index].repostCount += wasReposted ? -1 : 1

        Task {
            do {
                if wasReposted {
                    try await api.requestVoid(Endpoints.unrepostPost(id: postId), method: .post)
                } else {
                    try await api.requestVoid(Endpoints.repostPost(id: postId), method: .post)
                }
            } catch {
                await MainActor.run {
                    guard let rollbackIndex = posts.firstIndex(where: { $0.id == postId }) else { return }
                    var rollbackViewer = viewerByPostId[postId] ?? FeedViewer(isLiked: false, isReposted: false)
                    rollbackViewer.isReposted = wasReposted
                    viewerByPostId[postId] = rollbackViewer
                    posts[rollbackIndex].repostCount += wasReposted ? 1 : -1
                }
            }
        }

        return nil
    }
}
