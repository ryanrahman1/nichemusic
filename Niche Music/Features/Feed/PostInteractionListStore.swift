//
//  PostInteractionListStore.swift
//  Niche Music
//

import Foundation
import Combine

@MainActor
final class PostInteractionListStore: ObservableObject {
    @Published private(set) var users: [PostInteractionUser] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published var errorMessage: String?

    let postId: String
    let kind: PostInteractionKind

    private let pageSize = 20
    private var nextCursor: String?
    private var hasMore = false

    init(postId: String, kind: PostInteractionKind) {
        self.postId = postId
        self.kind = kind
    }

    func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        nextCursor = nil
        hasMore = false
        users = []

        defer { isLoading = false }

        do {
            let page = try await fetchPage(requestCursor: nil)
            users = page.users
            nextCursor = page.nextCursor
            hasMore = page.hasMore
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(currentUser user: PostInteractionUser) async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        guard users.last?.id == user.id else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await fetchPage(requestCursor: nextCursor)
            let existing = Set(users.map(\.id))
            let appended = page.users.filter { !existing.contains($0.id) }
            users.append(contentsOf: appended)
            nextCursor = page.nextCursor
            hasMore = page.hasMore
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private struct InteractionPage {
        let users: [PostInteractionUser]
        let nextCursor: String?
        let hasMore: Bool
    }

    private func fetchPage(requestCursor: String?) async throws -> InteractionPage {
        var query: [String: String?] = [
            "limit": String(pageSize),
            "cursorCreatedAt": nil,
            "cursorUserId": nil,
        ]

        if let cursor = PostInteractionCursor(rawValue: requestCursor) {
            query["cursorCreatedAt"] = cursor.cursorCreatedAt
            query["cursorUserId"] = cursor.cursorUserId
        }

        let endpoint: APIEndpoint = switch kind {
        case .likes: Endpoints.postLikes(id: postId)
        case .reposts: Endpoints.postReposts(id: postId)
        }

        let response: (result: PostInteractionsResponse, metadata: APIMetadata?) =
            try await APIClient.shared.requestWithMetadata(
                endpoint,
                method: .get,
                query: query
            )

        let pagination = response.metadata?.pagination
        return InteractionPage(
            users: response.result.users,
            nextCursor: pagination?.nextCursor,
            hasMore: pagination?.hasMore ?? false
        )
    }
}
