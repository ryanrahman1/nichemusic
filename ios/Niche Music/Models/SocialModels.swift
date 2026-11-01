//
//  SocialModels.swift
//  Niche Music
//

import Foundation

struct FollowRequestItem: Decodable, Identifiable, Equatable {
    let followerId: String
    let status: String
    let createdAt: String
    let user: FollowListProfile

    var id: String { followerId }
}

struct FollowRequestsResponse: Decodable {
    let followRequests: [FollowRequestItem]
}

struct BlocksListResponse: Decodable {
    let blocks: [String]
}

struct UpdatePostContentBody: Encodable {
    var caption: String?
}

struct UpdatePostBody: Encodable {
    var visibility: PostVisibility?
    var content: UpdatePostContentBody?
}

struct UpdatePostResponse: Decodable {
    let post: Post
    let viewer: PostViewerDetail
}

struct DeletePostResponse: Decodable {
    let message: String
}

struct DeleteCommentResponse: Decodable {
    let message: String
}
