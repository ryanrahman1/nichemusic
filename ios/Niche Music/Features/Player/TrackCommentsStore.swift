//
//  TrackCommentsStore.swift
//  Niche Music
//

import Foundation
import Combine

@MainActor
final class TrackCommentsStore: ObservableObject {
    @Published private(set) var commentsByTrackId: [String: [TrackComment]] = [:]
    @Published private(set) var repliesByCommentId: [String: [TrackComment]] = [:]
    @Published private(set) var commentsLoadingByTrackId: [String: Bool] = [:]
    @Published private(set) var repliesLoadingByCommentId: [String: Bool] = [:]
    @Published private(set) var commentsErrorByTrackId: [String: String?] = [:]
    @Published private(set) var repliesErrorByCommentId: [String: String?] = [:]
    @Published private(set) var isSendingByTrackId: [String: Bool] = [:]

    private var commentsLoadedAtByTrackId: [String: Date] = [:]
    private var inFlightCommentsTasks: [String: Task<[TrackComment], Error>] = [:]
    private var paginationByTrackId: [String: CommentPaginationState] = [:]
    private var paginationByReplyRootId: [String: CommentPaginationState] = [:]

    private let commentsTtl: TimeInterval = 30
    private let pageSize = 15
    private let api = APIClient.shared

    private struct CommentPaginationState {
        var nextCursor: String?
        var hasMore: Bool
    }

    func comments(for trackId: String) -> [TrackComment] {
        commentsByTrackId[trackId] ?? []
    }

    func replies(for commentId: String) -> [TrackComment] {
        repliesByCommentId[commentId] ?? []
    }

    func isLoading(trackId: String) -> Bool {
        commentsLoadingByTrackId[trackId] ?? false
    }

    func isLoadingReplies(commentId: String) -> Bool {
        repliesLoadingByCommentId[commentId] ?? false
    }

    func error(trackId: String) -> String? {
        commentsErrorByTrackId[trackId] ?? nil
    }

    func repliesError(commentId: String) -> String? {
        repliesErrorByCommentId[commentId] ?? nil
    }

    func isSending(trackId: String) -> Bool {
        isSendingByTrackId[trackId] ?? false
    }

    func loadTrackComments(trackId: String, force: Bool = false) async {
        do {
            _ = try await fetchTrackComments(trackId: trackId, force: force, reset: true)
        } catch {
            commentsErrorByTrackId[trackId] = error.localizedDescription
        }
    }

    func loadMoreTrackComments(trackId: String) async {
        guard paginationByTrackId[trackId]?.hasMore == true else { return }
        guard commentsLoadingByTrackId[trackId] != true else { return }

        do {
            _ = try await fetchTrackComments(trackId: trackId, force: true, reset: false)
        } catch {
            commentsErrorByTrackId[trackId] = error.localizedDescription
        }
    }

    func loadReplies(trackId: String, commentId: String, force: Bool = false) async {
        do {
            _ = try await fetchReplies(trackId: trackId, commentId: commentId, force: force, reset: true)
        } catch {
            repliesErrorByCommentId[commentId] = error.localizedDescription
        }
    }

    func loadMoreReplies(trackId: String, commentId: String) async {
        guard paginationByReplyRootId[commentId]?.hasMore == true else { return }
        guard repliesLoadingByCommentId[commentId] != true else { return }

        do {
            _ = try await fetchReplies(trackId: trackId, commentId: commentId, force: true, reset: false)
        } catch {
            repliesErrorByCommentId[commentId] = error.localizedDescription
        }
    }

    func toggleLike(trackId: String, commentId: String) async {
        let wasLiked = isCommentLiked(commentId: commentId)
        applyLikeState(commentId: commentId, isLiked: !wasLiked, delta: wasLiked ? -1 : 1)

        do {
            if wasLiked {
                try await api.requestVoid(Endpoints.unlikeNicheComment(id: commentId), method: .post)
            } else {
                try await api.requestVoid(Endpoints.likeNicheComment(id: commentId), method: .post)
            }
        } catch {
            applyLikeState(commentId: commentId, isLiked: wasLiked, delta: wasLiked ? 1 : -1)
        }
    }

    func sendTextComment(
        trackId: String,
        text: String,
        parentCommentId: String? = nil,
        replyToCommentId: String? = nil
    ) async throws {
        let body = CreateTextCommentBody(
            text: text,
            parentCommentId: parentCommentId,
            replyToCommentId: replyToCommentId
        )
        try await sendComment(trackId: trackId, body: body, parentCommentId: parentCommentId)
    }

    func sendGifComment(
        trackId: String,
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
        try await sendComment(trackId: trackId, body: body, parentCommentId: parentCommentId)
    }

    func sendTrackComment(
        trackId: String,
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
        try await sendComment(trackId: trackId, body: body, parentCommentId: parentCommentId)
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

    func setPinned(trackId: String, commentId: String, pinned: Bool) async throws {
        if pinned {
            try await api.requestVoid(Endpoints.pinNicheComment(id: commentId), method: .post)
        } else {
            try await api.requestVoid(Endpoints.unpinNicheComment(id: commentId), method: .post)
        }
        await reloadAffectedThreads(trackId: trackId, parentCommentId: nil)
    }

    func setHidden(trackId: String, commentId: String, hidden: Bool) async throws {
        if hidden {
            try await api.requestVoid(Endpoints.hideNicheComment(id: commentId), method: .post)
        } else {
            try await api.requestVoid(Endpoints.unhideNicheComment(id: commentId), method: .post)
        }
        await reloadAffectedThreads(trackId: trackId, parentCommentId: nil)
    }

    func deleteComment(trackId: String, commentId: String, parentCommentId: String?) async throws {
        try await api.requestVoid(Endpoints.deleteNicheComment(id: commentId), method: .post)
        removeCommentLocally(commentId: commentId, trackId: trackId, parentCommentId: parentCommentId)
    }

    private func removeCommentLocally(commentId: String, trackId: String, parentCommentId: String?) {
        if let parentCommentId {
            repliesByCommentId[parentCommentId] = (repliesByCommentId[parentCommentId] ?? [])
                .filter { $0.id != commentId }
            if var comments = commentsByTrackId[trackId],
               let index = comments.firstIndex(where: { $0.id == parentCommentId }) {
                comments[index].replyCount = max(0, comments[index].replyCount - 1)
                commentsByTrackId[trackId] = comments
            }
        } else {
            commentsByTrackId[trackId] = (commentsByTrackId[trackId] ?? [])
                .filter { $0.id != commentId }
        }
    }

    // MARK: - Private

    @discardableResult
    private func fetchTrackComments(trackId: String, force: Bool, reset: Bool) async throws -> [TrackComment] {
        if !force && reset,
           let cached = commentsByTrackId[trackId],
           let loadedAt = commentsLoadedAtByTrackId[trackId],
           Date().timeIntervalSince(loadedAt) < commentsTtl {
            return cached
        }

        if reset, let task = inFlightCommentsTasks[trackId] {
            return try await task.value
        }

        commentsLoadingByTrackId[trackId] = true
        commentsErrorByTrackId[trackId] = nil

        let cursor = reset ? nil : paginationByTrackId[trackId]?.nextCursor
        var query: [String: String?] = ["limit": String(pageSize)]
        if let cursor { query["cursor"] = cursor }

        do {
            let response: (result: TrackCommentsResponse, metadata: APIMetadata?) =
                try await api.requestWithMetadata(
                    Endpoints.getTrackComments(id: trackId),
                    method: .get,
                    query: query
                )

            let incoming = response.result.comments
            if reset {
                commentsByTrackId[trackId] = incoming
            } else {
                var merged = commentsByTrackId[trackId] ?? []
                let existingIds = Set(merged.map(\.id))
                merged.append(contentsOf: incoming.filter { !existingIds.contains($0.id) })
                commentsByTrackId[trackId] = merged
            }

            paginationByTrackId[trackId] = CommentPaginationState(
                nextCursor: response.metadata?.pagination?.nextCursor,
                hasMore: response.metadata?.pagination?.hasMore ?? false
            )
            commentsLoadedAtByTrackId[trackId] = Date()
            commentsLoadingByTrackId[trackId] = false
            inFlightCommentsTasks[trackId] = nil
            return commentsByTrackId[trackId] ?? []
        } catch {
            commentsLoadingByTrackId[trackId] = false
            inFlightCommentsTasks[trackId] = nil
            throw error
        }
    }

    @discardableResult
    private func fetchReplies(trackId: String, commentId: String, force: Bool, reset: Bool) async throws -> [TrackComment] {
        repliesLoadingByCommentId[commentId] = true
        repliesErrorByCommentId[commentId] = nil

        let cursor = reset ? nil : paginationByReplyRootId[commentId]?.nextCursor
        var query: [String: String?] = ["limit": String(pageSize)]
        if let cursor { query["cursor"] = cursor }

        do {
            let response: (result: TrackCommentsResponse, metadata: APIMetadata?) =
                try await api.requestWithMetadata(
                    Endpoints.nicheTrackCommentReplies(trackId: trackId, commentId: commentId),
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

    private func sendComment(trackId: String, body: Encodable, parentCommentId: String?) async throws {
        isSendingByTrackId[trackId] = true
        defer { isSendingByTrackId[trackId] = false }

        let _: CommentMutationResponse = try await api.request(
            Endpoints.createNicheTrackComment(trackId: trackId),
            method: .post,
            body: body,
            preserveBodyKeyNames: true
        )

        await reloadAffectedThreads(trackId: trackId, parentCommentId: parentCommentId)
    }

    private func reloadAffectedThreads(trackId: String, parentCommentId: String?) async {
        await loadTrackComments(trackId: trackId, force: true)
        if let parentCommentId {
            await loadReplies(trackId: trackId, commentId: parentCommentId, force: true)
        }
    }

    private func applyLikeState(commentId: String, isLiked: Bool, delta: Int) {
        for trackId in commentsByTrackId.keys {
            guard var comments = commentsByTrackId[trackId],
                  let index = comments.firstIndex(where: { $0.id == commentId }) else { continue }
            comments[index].viewer = TrackCommentViewer(
                isLiked: isLiked,
                isOwner: comments[index].viewer?.isOwner
            )
            comments[index].likeCount = max(0, comments[index].likeCount + delta)
            commentsByTrackId[trackId] = comments
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
        if let comments = commentsByTrackId.values.flatMap({ $0 }).first(where: { $0.id == commentId }) {
            return comments.viewer?.isLiked == true
        }
        if let reply = repliesByCommentId.values.flatMap({ $0 }).first(where: { $0.id == commentId }) {
            return reply.viewer?.isLiked == true
        }
        return false
    }
}
