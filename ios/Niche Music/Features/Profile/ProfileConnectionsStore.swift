//
//  ProfileConnectionsStore.swift
//  Niche Music
//

import Foundation
import Combine

@MainActor
final class ProfileConnectionsStore: ObservableObject {
    let kind: ProfileConnectionsKind
    /// When `nil`, loads the authenticated user's list via `/me/...`.
    let username: String?

    @Published private(set) var users: [FollowListProfile] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let api = APIClient.shared

    init(kind: ProfileConnectionsKind, username: String? = nil) {
        self.kind = kind
        self.username = username
    }

    func load() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            switch kind {
            case .followers:
                users = try await fetchFollowers()
            case .following:
                users = try await fetchFollowing()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchFollowers() async throws -> [FollowListProfile] {
        let endpoint: APIEndpoint
        if let username {
            endpoint = Endpoints.userFollowers(username: username)
        } else {
            endpoint = Endpoints.myFollowers
        }

        let response: FollowersListResponse = try await api.request(endpoint, method: .get)
        return response.followers
    }

    private func fetchFollowing() async throws -> [FollowListProfile] {
        let endpoint: APIEndpoint
        if let username {
            endpoint = Endpoints.userFollowing(username: username)
        } else {
            endpoint = Endpoints.myFollowing
        }

        let response: FollowingListResponse = try await api.request(endpoint, method: .get)
        return response.following
    }
}
