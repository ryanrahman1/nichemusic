//
//  PostCommentsStore.swift
//  Niche Music
//

import Foundation
import Combine

@MainActor
final class PostCommentsStore: ObservableObject {
    @Published private(set) var commentsByPostId: [String: [TrackComment]] = [:]
    @Published private(set) var repliesByCommentId: [String: [TrackComment]] = [:]
    @Published private(set) var commentsLoadingByPostId: [String: Bool] = [:]
    @Published private(set) var repliesLoadingByCommentId: [String: Bool] = [:]
    @Published private(set) var commentsErrorByPostId: [String: String?] = [:]
    @Published private(set) var repliesErrorByCommentId: [String: String?] = [:]
    @Published private(set) var isSendingByPostId: [String: Bool] = [:]

    private var commentsLoadedAtByPostId: [String: Date] = [:]
    private var inFlightCommentsTasks: [String: Task<[TrackComment], Error>] = [:]
    private var paginationByPostId: [String: CommentPaginationState] = [:]
    private var paginationByReplyRootId: [String: CommentPaginationState] = [:]

    private let commentsTtl: TimeInterval = 30
    private let pageSize = 15
    private let api = APIClient.shared

    private struct CommentPaginationState {
        var nextCursor: String?
        var hasMore: Bool
    }

    func comments(for postId: String) -> [TrackComment] {
        commentsByPostId[postId] ?? []
    }

    func replies(for commentId: String) -> [TrackComment] {
        repliesByCommentId[commentId] ?? []
    }

    func isLoading(postId: String) -> Bool {
        commentsLoadingByPostId[postId] ?? false
    }

    func isLoadingReplies(commentId: String) -> Bool {
        repliesLoadingByCommentId[commentId] ?? false
    }

    func error(postId: String) -> String? {
        commentsErrorByPostId[postId] ?? nil
    }

    func repliesError(commentId: String) -> String? {
        repliesErrorByCommentId[commentId] ?? nil
    }

    func isSending(postId: String) -> Bool {
        isSendingByPostId[postId] ?? false
    }

    func loadPostComments(postId: String, force: Bool = false) async {
        do {
            _ = try await fetchPostComments(postId: postId, force: force, reset: true)
        } catch {
            commentsErrorByPostId[postId] = error.localizedDescription
        }
    }

    func loadMorePostComments(postId: String) async {
        guard paginationByPostId[postId]?.hasMore == true else { return }
        guard commentsLoadingByPostId[postId] != true else { return }

        do {
            _ = try await fetchPostComments(postId: postId, force: true, reset: false)
        } catch {
            commentsErrorByPostId[postId] = error.localizedDescription
        }
    }

    func loadReplies(postId: String, commentId: String, force: Bool = false) async {
        do {
            _ = try await fetchReplies(postId: postId, commentId: commentId, force: force, reset: true)
        } catch {
            repliesErrorByCommentId[commentId] = error.localizedDescription
        }
    }

    func loadMoreReplies(postId: String, commentId: String) async {
        guard paginationByReplyRootId[commentId]?.hasMore == true else { return }
        guard repliesLoadingByCommentId[commentId] != true else { return }

        do {
            _ = try await fetchReplies(postId: postId, commentId: commentId, force: true, reset: false)
        } catch {
            repliesErrorByCommentId[commentId] = error.localizedDescription
        }
    }

    func toggleLike(postId: String, commentId: String) async {
        let wasLiked = isCommentLiked(commentId: commentId)
        applyLikeState(commentId: commentId, isLiked: !wasLiked, delta: wasLiked ? -1 : 1)

        do {
            if wasLiked {
                try await api.requestVoid(Endpoints.unlikeComment(id: commentId), method: .post)
            } else {
                try await api.requestVoid(Endpoints.likeComment(id: commentId), method: .post)
            }
        } catch {
            applyLikeState(commentId: commentId, isLiked: wasLiked, delta: wasLiked ? 1 : -1)
        }
    }

    func sendTextComment(
        postId: String,
        text: String,
        parentCommentId: String? = nil,
        replyToCommentId: String? = nil
    ) async throws {
        let body = CreateTextCommentBody(
            text: text,
            parentCommentId: parentCommentId,
            replyToCommentId: replyToCommentId
        )
        try await sendComment(postId: postId, body: body, parentCommentId: parentCommentId)
    }

    func sendGifComment(
        postId: String,
        gif: GiphyPickResult,
        parentCommentId: String? = nil,
        replyToCommentId: String? = nil
    ) async throws {
        let body = CreateGifCommentBody(
            text: "",
            gif: CreateCommentGifBody(
                id: gif.id,
                url: gif.url,
                width: gif.width,
                height: gif.height
            ),
            parentCommentId: parentCommentId,
            replyToCommentId: replyToCommentId
        )
        try await sendComment(postId: postId, body: body, parentCommentId: parentCommentId)
    }

    func sendTrackComment(
        postId: String,
        appleSongId: String,
        parentCommentId: String? = nil,
        replyToCommentId: String? = nil
    ) async throws {
        let detail: AppleSongIdLookupResponse = try await api.request(
            Endpoints.appleMusicSong(id: appleSongId),
            method: .get
        )

        let body = CreateTrackCommentBody(
            trackId: detail.track.id,
            text: "",
            parentCommentId: parentCommentId,
            replyToCommentId: replyToCommentId
        )
        try await sendComment(postId: postId, body: body, parentCommentId: parentCommentId)
    }

    func searchAppleSongs(query: String) async throws -> [AppleMusicSearchSong] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let response: AppleMusicSearchResponse = try await api.request(
            Endpoints.appleMusicSearch,
            method: .get,
            query: [
                "q": trimmed,
                "types": "songs",
            ]
        )

        return response.data.results?.songs?.data ?? []
    }

    func setPinned(postId: String, commentId: String, pinned: Bool) async throws {
        if pinned {
            try await api.requestVoid(Endpoints.pinComment(id: commentId), method: .post)
        } else {
            try await api.requestVoid(Endpoints.unpinComment(id: commentId), method: .post)
        }
        await reloadAffectedThreads(postId: postId, parentCommentId: nil)
    }

    func setHidden(postId: String, commentId: String, hidden: Bool) async throws {
        if hidden {
            try await api.requestVoid(Endpoints.hideComment(id: commentId), method: .post)
        } else {
            try await api.requestVoid(Endpoints.unhideComment(id: commentId), method: .post)
        }
        await reloadAffectedThreads(postId: postId, parentCommentId: nil)
    }

    func deleteComment(postId: String, commentId: String, parentCommentId: String?) async throws {
        try await api.requestVoid(Endpoints.deleteComment(id: commentId), method: .post)
        removeCommentLocally(commentId: commentId, postId: postId, parentCommentId: parentCommentId)
    }

    private func removeCommentLocally(commentId: String, postId: String, parentCommentId: String?) {
        if let parentCommentId {
            repliesByCommentId[parentCommentId] = (repliesByCommentId[parentCommentId] ?? [])
                .filter { $0.id != commentId }
            if var comments = commentsByPostId[postId],
               let index = comments.firstIndex(where: { $0.id == parentCommentId }) {
                comments[index].replyCount = max(0, comments[index].replyCount - 1)
                commentsByPostId[postId] = comments
            }
        } else {
            commentsByPostId[postId] = (commentsByPostId[postId] ?? [])
                .filter { $0.id != commentId }
        }
    }

    // MARK: - Private

    @discardableResult
    private func fetchPostComments(postId: String, force: Bool, reset: Bool) async throws -> [TrackComment] {
        if !force && reset,
           let cached = commentsByPostId[postId],
           let loadedAt = commentsLoadedAtByPostId[postId],
           Date().timeIntervalSince(loadedAt) < commentsTtl {
            return cached
        }

        if reset, let task = inFlightCommentsTasks[postId] {
            return try await task.value
        }

        commentsLoadingByPostId[postId] = true
        commentsErrorByPostId[postId] = nil

        let cursor = reset ? nil : paginationByPostId[postId]?.nextCursor
        var query: [String: String?] = ["limit": String(pageSize)]
        if let cursor { query["cursor"] = cursor }

        do {
            let response: (result: TrackCommentsResponse, metadata: APIMetadata?) =
                try await api.requestWithMetadata(
                    Endpoints.getPostComments(id: postId),
                    method: .get,
                    query: query
                )

            let incoming = response.result.comments
            if reset {
                commentsByPostId[postId] = incoming
            } else {
                var merged = commentsByPostId[postId] ?? []
                let existingIds = Set(merged.map(\.id))
                merged.append(contentsOf: incoming.filter { !existingIds.contains($0.id) })
                commentsByPostId[postId] = merged
            }

            paginationByPostId[postId] = CommentPaginationState(
                nextCursor: response.metadata?.pagination?.nextCursor,
                hasMore: response.metadata?.pagination?.hasMore ?? false
            )
            commentsLoadedAtByPostId[postId] = Date()
            commentsLoadingByPostId[postId] = false
            inFlightCommentsTasks[postId] = nil
            return commentsByPostId[postId] ?? []
        } catch {
            commentsLoadingByPostId[postId] = false
            inFlightCommentsTasks[postId] = nil
            throw error
        }
    }

    @discardableResult
    private func fetchReplies(postId: String, commentId: String, force: Bool, reset: Bool) async throws -> [TrackComment] {
        repliesLoadingByCommentId[commentId] = true
        repliesErrorByCommentId[commentId] = nil

        let cursor = reset ? nil : paginationByReplyRootId[commentId]?.nextCursor
        var query: [String: String?] = ["limit": String(pageSize)]
        if let cursor { query["cursor"] = cursor }

        do {
            let response: (result: TrackCommentsResponse, metadata: APIMetadata?) =
                try await api.requestWithMetadata(
                    Endpoints.postCommentReplies(postId: postId, commentId: commentId),
                    method: .get,
                    query: query
                )

            let incoming = response.result.comments
            if reset {
                repliesByCommentId[commentId] = incoming
            } else {
                var merged = repliesByCommentId[commentId] ?? []
                let existingIds = Set(merged.map(\.id))
                merged.append(contentsOf: incoming.filter { !existingIds.contains($0.id) })
                repliesByCommentId[commentId] = merged
            }

            paginationByReplyRootId[commentId] = CommentPaginationState(
                nextCursor: response.metadata?.pagination?.nextCursor,
                hasMore: response.metadata?.pagination?.hasMore ?? false
            )
            repliesLoadingByCommentId[commentId] = false
            return repliesByCommentId[commentId] ?? []
        } catch {
            repliesLoadingByCommentId[commentId] = false
            throw error
        }
    }

    private func sendComment(postId: String, body: Encodable, parentCommentId: String?) async throws {
        isSendingByPostId[postId] = true
        defer { isSendingByPostId[postId] = false }

        let _: CommentMutationResponse = try await api.request(
            Endpoints.createPostComment(postId: postId),
            method: .post,
            body: body,
            preserveBodyKeyNames: true
        )

        await reloadAffectedThreads(postId: postId, parentCommentId: parentCommentId)
    }

    private func reloadAffectedThreads(postId: String, parentCommentId: String?) async {
        await loadPostComments(postId: postId, force: true)
        if let parentCommentId {
            await loadReplies(postId: postId, commentId: parentCommentId, force: true)
        }
    }

    private func applyLikeState(commentId: String, isLiked: Bool, delta: Int) {
        for postId in commentsByPostId.keys {
            guard var comments = commentsByPostId[postId],
                  let index = comments.firstIndex(where: { $0.id == commentId }) else { continue }
            comments[index].viewer = TrackCommentViewer(
                isLiked: isLiked,
                isOwner: comments[index].viewer?.isOwner
            )
            comments[index].likeCount = max(0, comments[index].likeCount + delta)
            commentsByPostId[postId] = comments
        }

        for rootId in repliesByCommentId.keys {
            guard var replies = repliesByCommentId[rootId],
                  let index = replies.firstIndex(where: { $0.id == commentId }) else { continue }
            replies[index].viewer = TrackCommentViewer(
                isLiked: isLiked,
                isOwner: replies[index].viewer?.isOwner
            )
            replies[index].likeCount = max(0, replies[index].likeCount + delta)
            repliesByCommentId[rootId] = replies
        }
    }

    private func isCommentLiked(commentId: String) -> Bool {
        if let comments = commentsByPostId.values.flatMap({ $0 }).first(where: { $0.id == commentId }) {
            return comments.viewer?.isLiked == true
        }
        if let reply = repliesByCommentId.values.flatMap({ $0 }).first(where: { $0.id == commentId }) {
            return reply.viewer?.isLiked == true
        }
        return false
    }
}
