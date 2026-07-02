//
//  NotificationModels.swift
//  Niche Music
//

import Foundation

struct NotificationsListResponse: Decodable {
    let notifications: [AppNotification]
}

struct NotificationData: Equatable {
    let values: [String: String]

    var actorId: String? { string("actorId", "actor_id") }
    var actorUsername: String? { string("actorUsername", "actor_username") }
    var postId: String? { string("postId", "post_id") }
    var commentId: String? { string("commentId", "comment_id") }
    var trackId: String? { string("trackId", "track_id") }
    var conversationId: String? { string("conversationId", "conversation_id") }
    var messageId: String? { string("messageId", "message_id") }
    var link: String? { string("link") }
    var url: String? { string("url") }
    var path: String? { string("path") }

    func string(_ keys: String...) -> String? {
        for key in keys {
            guard let raw = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { continue }
            return raw
        }
        return nil
    }
}

extension NotificationData: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let dictionary = try? container.decode([String: String].self) {
            values = dictionary
            return
        }

        if let dictionary = try? container.decode([String: LossyString].self) {
            values = dictionary.mapValues(\.value)
            return
        }

        values = [:]
    }
}

private struct LossyString: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
            return
        }
        if let bool = try? container.decode(Bool.self) {
            value = bool ? "true" : "false"
            return
        }
        if let int = try? container.decode(Int.self) {
            value = String(int)
            return
        }
        if let double = try? container.decode(Double.self) {
            value = String(double)
            return
        }
        value = ""
    }
}

struct AppNotification: Decodable, Identifiable, Equatable {
    let id: String
    let recipientId: String
    let actorId: String?
    let kind: String
    let entityType: String
    let entityId: String?
    let title: String
    let body: String
    let imageUrl: String?
    let data: NotificationData?
    let isRead: Bool
    let readAt: String?
    let createdAt: String

    init(
        id: String,
        recipientId: String,
        actorId: String?,
        kind: String,
        entityType: String,
        entityId: String?,
        title: String,
        body: String,
        imageUrl: String?,
        data: NotificationData?,
        isRead: Bool,
        readAt: String?,
        createdAt: String
    ) {
        self.id = id
        self.recipientId = recipientId
        self.actorId = actorId
        self.kind = kind
        self.entityType = entityType
        self.entityId = entityId
        self.title = title
        self.body = body
        self.imageUrl = imageUrl
        self.data = data
        self.isRead = isRead
        self.readAt = readAt
        self.createdAt = createdAt
    }

    func markedRead() -> AppNotification {
        AppNotification(
            id: id,
            recipientId: recipientId,
            actorId: actorId,
            kind: kind,
            entityType: entityType,
            entityId: entityId,
            title: title,
            body: body,
            imageUrl: imageUrl,
            data: data,
            isRead: true,
            readAt: readAt ?? ISO8601DateFormatter().string(from: Date()),
            createdAt: createdAt
        )
    }
}

struct NotificationReadResponse: Decodable {
    let notification: AppNotification
}
