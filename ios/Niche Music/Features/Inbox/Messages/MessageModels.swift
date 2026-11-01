//
//  MessageModels.swift
//  Niche Music
//
//  Created by Ryan Rahman on 6/9/26.
//

import Foundation

enum ChatKind: Hashable {
    case dm
    case group
}

enum MessageAttachmentKind {
    case song
    case album
    case artist
    case gif
    case profile
}

struct ChatPreview: Identifiable, Hashable {
    let id: String
    let kind: ChatKind
    var name: String
    let subtitle: String
    let avatarURL: String?
    let memberAvatarURLs: [String]
    let lastMessage: String
    let time: String
    let unreadCount: Int
    let otherUserId: String?
    let otherUsername: String?
    let memberNames: [String]
}

struct MessageComposeRecipient: Equatable, Hashable, Identifiable {
    let id: String
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let profileType: String?

    var resolvedDisplayName: String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? username : trimmed
    }

    init(user: MessageUserSummary) {
        id = user.id
        username = user.username
        displayName = user.displayName
        avatarUrl = user.avatarUrl
        profileType = user.profileType
    }

    init(otherUser: MusicMatchOtherUser) {
        id = otherUser.id
        username = otherUser.username
        displayName = otherUser.displayName
        avatarUrl = otherUser.avatarUrl
        profileType = otherUser.profileType
    }

    init(profile user: FullUser) {
        id = user.id
        username = user.username
        displayName = user.displayName
        avatarUrl = user.avatarUrl
        profileType = user.profileType
    }
}

struct MessageComposeIntent: Identifiable, Equatable, Hashable {
    let id = UUID()
    let recipient: MessageComposeRecipient?
    let conversationId: String?
}

struct ChatMessage: Identifiable {
    let id: String
    let kind: String
    let senderId: String
    let senderName: String
    let senderAvatarURL: String?
    let text: String?
    let caption: String?
    let isMine: Bool
    let createdAt: String
    let timestamp: String
    let isSending: Bool
    let readReceiptLabel: String?
    let attachment: MessageAttachment?
}

struct MessageAttachment: Identifiable {
    let id: String
    let kind: MessageAttachmentKind
    let title: String
    let subtitle: String?
    let imageURL: String?
    let gifURL: String?
    let gifWidth: Int?
    let gifHeight: Int?
    let username: String?
    let entityId: String?
    let source: String?
    let sourceId: String?
}

enum ThreadListItem: Identifiable {
    case separator(id: String, label: String)
    case message(ChatMessage, showSenderLabel: Bool)

    var id: String {
        switch self {
        case .separator(let id, _):
            return id
        case .message(let message, _):
            return message.id
        }
    }
}
