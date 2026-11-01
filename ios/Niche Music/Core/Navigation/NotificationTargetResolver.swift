//
//  NotificationTargetResolver.swift
//  Niche Music
//

import Foundation

enum NotificationTargetResolver {
    static func destination(for notification: AppNotification) -> DeepLinkDestination? {
        resolve(
            kind: notification.kind,
            entityType: notification.entityType,
            entityId: notification.entityId,
            actorId: notification.actorId,
            data: notification.data
        )
    }

    static func destination(fromPushPayload userInfo: [AnyHashable: Any]) -> DeepLinkDestination? {
        let payload = flattenPushPayload(userInfo)
        return resolve(
            kind: payload.string("kind"),
            entityType: payload.string("entity_type", "entityType"),
            entityId: payload.string("entity_id", "entityId"),
            actorId: payload.string("actor_id", "actorId"),
            data: payload
        )
    }

    private static func resolve(
        kind: String?,
        entityType: String?,
        entityId: String?,
        actorId: String?,
        data: NotificationData?
    ) -> DeepLinkDestination? {
        if kind == "message",
           let conversationId = data?.conversationId ?? (entityType == "system" ? entityId : nil) {
            return .conversation(id: conversationId)
        }

        if let trackId = data?.trackId ?? (entityType == "track" ? entityId : nil),
           isTrackKind(kind) {
            return .track(TrackDetailReference(id: trackId, source: "niche", sourceId: nil))
        }

        if let postId = data?.postId ?? (entityType == "post" ? entityId : nil) {
            return .post(id: postId, commentId: data?.commentId)
        }

        if let link = data?.link ?? data?.url ?? data?.path {
            if let destination = NicheURLParser.parse(link) {
                return destination
            }
            if let url = URL(string: link), link.contains("://") {
                return .externalURL(url)
            }
        }

        if let username = data?.actorUsername,
           entityType == "profile" || isProfileKind(kind) {
            return .profile(username: username)
        }

        if entityType == "profile", let profileId = entityId ?? actorId, !profileId.isEmpty {
            if let username = data?.actorUsername {
                return .profile(username: username)
            }
        }

        return nil
    }

    private static func flattenPushPayload(_ userInfo: [AnyHashable: Any]) -> NotificationData {
        var merged: [String: String] = [:]

        func absorb(_ dictionary: [AnyHashable: Any]) {
            for (key, value) in dictionary {
                guard let keyString = key as? String else { continue }
                if keyString == "data", let nested = value as? [AnyHashable: Any] {
                    absorb(nested)
                    continue
                }
                if let string = stringValue(value) {
                    merged[keyString] = string
                }
            }
        }

        absorb(userInfo)
        return NotificationData(values: merged)
    }

    private static func stringValue(_ value: Any) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        case let bool as Bool:
            return bool ? "true" : "false"
        default:
            return nil
        }
    }

    private static func isProfileKind(_ kind: String?) -> Bool {
        switch kind {
        case "follow", "follow_request", "follow_accept":
            return true
        default:
            return false
        }
    }

    private static func isTrackKind(_ kind: String?) -> Bool {
        switch kind {
        case "track_comment", "track_comment_reply", "track_comment_like":
            return true
        default:
            return false
        }
    }
}
