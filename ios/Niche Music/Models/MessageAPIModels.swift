//
//  MessageAPIModels.swift
//  Niche Music
//

import Foundation

struct InboxResponse: Decodable {
    let inbox: [InboxRow]
}

struct InboxRow: Decodable, Identifiable {
    let id: String
    let createdAt: String
    let lastMessageAt: String?
    let otherUser: InboxOtherUser?
    let conversationType: String?
    let title: String?
    let members: [InboxOtherUser]?
    let lastReadMessageId: String?
    let lastReadAt: String?
    let lastMessage: InboxLastMessage?

    func updating(
        lastMessageAt: String? = nil,
        lastReadMessageId: String? = nil,
        lastReadAt: String? = nil,
        lastMessage: InboxLastMessage? = nil
    ) -> InboxRow {
        InboxRow(
            id: id,
            createdAt: createdAt,
            lastMessageAt: lastMessageAt ?? self.lastMessageAt,
            otherUser: otherUser,
            conversationType: conversationType,
            title: title,
            members: members,
            lastReadMessageId: lastReadMessageId ?? self.lastReadMessageId,
            lastReadAt: lastReadAt ?? self.lastReadAt,
            lastMessage: lastMessage ?? self.lastMessage
        )
    }
}

struct InboxOtherUser: Decodable {
    let id: String
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let profileType: String?
    let typeUpdatedAt: String?
}

struct InboxLastMessage: Decodable {
    let id: String
    let conversationId: String
    let senderId: String
    let kind: String
    let createdAt: String
    let textPlain: String?
    let content: MessageContentPayload?
}

struct MessageContentPayload: Decodable {
    let text: String?
    let trackId: String?
    let albumId: String?
    let artistId: String?
    let userId: String?
    let caption: String?
    let gifUrl: String?
    let width: Int?
    let height: Int?
    let provider: String?
}

struct ConversationPageResponse: Decodable {
    let conversationId: String
    let messages: [ConversationMessage]
    let readStates: [ConversationReadState]
    let nextCursor: String?
    let hasMore: Bool
}

struct ConversationMessage: Decodable, Identifiable {
    let id: String
    let conversationId: String
    let senderId: String
    let kind: String
    let createdAt: String
    let textPlain: String?
    let content: MessageContentPayload?
    let clientId: String?
    let sender: InboxOtherUser?
    let entity: MessageEntity?
}

struct MessageEntity: Decodable {
    let id: String?
    let name: String?
    let source: String?
    let sourceId: String?
    let artworkUrl: String?
    let imageUrl: String?
    let avatarUrl: String?
    let username: String?
    let displayName: String?
    let artists: MessageEntityArtist?
}

struct MessageEntityArtist: Decodable {
    let name: String?
}

struct ConversationReadState: Decodable {
    let userId: String
    let lastReadMessageId: String?
    let lastReadAt: String?
}

struct CreateMessageResponse: Decodable {
    let message: ConversationMessage
}

struct MarkMessageReadResponse: Decodable {
    let conversationId: String
    let userId: String
    let lastReadMessageId: String
    let lastReadAt: String
}

struct EnsureDMResponse: Decodable {
    let conversationId: String
    let created: Bool?
}

struct CreateTextMessageBody: Encodable {
    let conversationId: String
    let clientId: String
    let kind: String
    let text: String
}

struct CreateTrackShareBody: Encodable {
    let conversationId: String
    let clientId: String
    let kind: String
    let trackId: String
    let caption: String?
}

struct CreateAlbumShareBody: Encodable {
    let conversationId: String
    let clientId: String
    let kind: String
    let albumId: String
    let caption: String?
}

struct CreateArtistShareBody: Encodable {
    let conversationId: String
    let clientId: String
    let kind: String
    let artistId: String
    let caption: String?
}

struct CreateProfileShareBody: Encodable {
    let conversationId: String
    let clientId: String
    let kind: String
    let userId: String
    let caption: String?
}

struct CreateGifBody: Encodable {
    let conversationId: String
    let clientId: String
    let kind: String
    let gifUrl: String
    let width: Int
    let height: Int
    let provider: String
    let caption: String?
}

struct MarkMessageReadBody: Encodable {
    let conversationId: String
    let messageId: String
}

struct EnsureDMBody: Encodable {
    let otherUserId: String
}

// Lookup responses — resolve Apple Music source ID → internal DB ID

struct AppleAlbumLookupResponse: Decodable {
    let album: EntityIdOnly
}

struct AppleArtistLookupResponse: Decodable {
    let artist: EntityIdOnly
}

struct EntityIdOnly: Decodable {
    let id: String
}

// Minimal user summary used by the profile share picker

struct MessageUserLookupResponse: Decodable {
    let user: MessageUserSummary
}

struct FriendsResponse: Decodable {
    let friends: [MessageUserSummary]
}

struct MessageUserSummary: Decodable, Identifiable {
    let id: String
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let profileType: String?
    let typeUpdatedAt: String?

    var resolvedDisplayName: String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? username : trimmed
    }
}
