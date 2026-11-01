//
//  PostInteractionModels.swift
//  Niche Music
//

import Foundation

enum PostInteractionKind: String {
    case likes
    case reposts

    var navigationTitle: String {
        switch self {
        case .likes: return "Likes"
        case .reposts: return "Reposts"
        }
    }
}

struct PostInteractionListItem: Identifiable {
    let postId: String
    let kind: PostInteractionKind

    var id: String { "\(kind.rawValue)-\(postId)" }
}

struct PostInteractionsResponse: Decodable {
    let users: [PostInteractionUser]
}

struct PostInteractionUser: Decodable, Identifiable, Equatable {
    let id: String
    let username: String
    let avatarUrl: String?
    let profileType: String?
    let typeUpdatedAt: String?
}

struct PostInteractionCursor: Codable {
    let cursorCreatedAt: String
    let cursorUserId: String

    init?(rawValue: String?) {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(PostInteractionCursor.self, from: data) else {
            return nil
        }
        self = decoded
    }
}
