//
//  ProfileConnectionsModels.swift
//  Niche Music
//

import Foundation

struct FollowListProfile: Decodable, Identifiable, Equatable {
    let id: String
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let profileType: String?
    let typeUpdatedAt: String?
}

struct FollowersListResponse: Decodable {
    let followers: [FollowListProfile]
}

struct FollowingListResponse: Decodable {
    let following: [FollowListProfile]
}

enum ProfileConnectionsKind {
    case followers
    case following

    var navigationTitle: String {
        switch self {
        case .followers: "Followers"
        case .following: "Following"
        }
    }

    var emptyTitle: String {
        switch self {
        case .followers: "No followers yet"
        case .following: "Not following anyone"
        }
    }
}
