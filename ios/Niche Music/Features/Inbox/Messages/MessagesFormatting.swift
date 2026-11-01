//
//  MessagesFormatting.swift
//  Niche Music
//

import Foundation

enum MessagesFormatting {
    static func previewLine(for message: InboxLastMessage?) -> String {
        guard let message else { return "No messages yet" }

        if let plain = message.textPlain?.trimmingCharacters(in: .whitespacesAndNewlines), !plain.isEmpty {
            return plain
        }

        if let text = message.content?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }

        switch message.kind {
        case "text": return "Message"
        case "track_share": return "Sent a track"
        case "gif": return "Sent a GIF"
        case "album_share": return "Sent an album"
        case "artist_share": return "Sent an artist"
        case "profile_share": return "Sent a profile"
        default: return "Message"
        }
    }

    static func previewLine(for message: ConversationMessage) -> String {
        if let plain = message.textPlain?.trimmingCharacters(in: .whitespacesAndNewlines), !plain.isEmpty {
            return plain
        }
        if let text = message.content?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        switch message.kind {
        case "text": return "Message"
        case "track_share": return "Sent a track"
        case "gif": return "Sent a GIF"
        case "album_share": return "Sent an album"
        case "artist_share": return "Sent an artist"
        case "profile_share": return "Sent a profile"
        default: return "Message"
        }
    }

    static func shortRelativeTime(_ iso: String?) -> String? {
        guard let iso, let date = parseISO8601(iso) else { return nil }

        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 45 { return "just now" }

        let minutes = seconds / 60
        if minutes < 60 { return minutes <= 1 ? "1m" : "\(minutes)m" }

        let hours = minutes / 60
        if hours < 24 { return hours == 1 ? "1h" : "\(hours)h" }

        let days = hours / 24
        if days < 7 { return days == 1 ? "1d" : "\(days)d" }

        let weeks = days / 7
        if weeks <= 3 { return weeks == 1 ? "1w" : "\(weeks)w" }
        return shortDateFormatter.string(from: date)
    }

    static func threadTimestamp(_ iso: String) -> String {
        guard let date = parseISO8601(iso) else { return "" }
        return threadTimeFormatter.string(from: date)
    }

    static func readReceiptTime(_ iso: String) -> String? {
        guard let date = parseISO8601(iso) else { return nil }
        return threadTimeFormatter.string(from: date)
    }

    static func messageTimeSeparatorLabel(_ iso: String) -> String? {
        guard let date = parseISO8601(iso) else { return nil }
        return timeSeparatorFormatter.string(from: date)
    }

    static func shouldShowTimeSeparator(previousCreatedAt: String?, nextCreatedAt: String) -> Bool {
        guard let previousCreatedAt,
              let previousDate = parseISO8601(previousCreatedAt),
              let nextDate = parseISO8601(nextCreatedAt) else {
            return false
        }
        return nextDate.timeIntervalSince(previousDate) > thirtyMinuteGap
    }

    static func threadListItems(
        from messages: [ChatMessage],
        isGroup: Bool
    ) -> [ThreadListItem] {
        var items: [ThreadListItem] = []

        for index in messages.indices {
            let message = messages[index]

            if index > 0 {
                let previous = messages[index - 1]
                if shouldShowTimeSeparator(
                    previousCreatedAt: previous.createdAt,
                    nextCreatedAt: message.createdAt
                ), let label = messageTimeSeparatorLabel(message.createdAt) {
                    items.append(.separator(id: "sep-\(message.id)", label: label))
                }
            }

            let showSenderLabel = isGroup && (
                index == 0 || messages[index - 1].senderId != message.senderId
            )
            items.append(.message(message, showSenderLabel: showSenderLabel))
        }

        return items
    }

    /// `messages` must be **newest-first** (matches inverted chat scroll).
    static func threadListItemsNewestFirst(
        from messages: [ChatMessage],
        isGroup: Bool
    ) -> [ThreadListItem] {
        var items: [ThreadListItem] = []

        for index in messages.indices {
            let message = messages[index]
            let showSenderLabel = isGroup && !message.isMine && (
                index + 1 >= messages.count
                    || messages[index + 1].senderId != message.senderId
            )

            items.append(.message(message, showSenderLabel: showSenderLabel))

            if index + 1 < messages.count {
                let newer = messages[index]
                let older = messages[index + 1]
                if shouldShowTimeSeparator(
                    previousCreatedAt: older.createdAt,
                    nextCreatedAt: newer.createdAt
                ), let label = messageTimeSeparatorLabel(newer.createdAt) {
                    items.append(.separator(id: "sep-\(older.id)", label: label))
                }
            }
        }

        return items
    }

    private static let thirtyMinuteGap: TimeInterval = 30 * 60

    static func hasUnread(selfUserId: String?, row: InboxRow) -> Bool {
        guard let selfUserId, let lastMessage = row.lastMessage else { return false }
        if lastMessage.senderId == selfUserId { return false }

        if row.conversationType != "group",
           let otherUser = row.otherUser,
           lastMessage.senderId != otherUser.id {
            return false
        }

        guard let lastReadAt = row.lastReadAt,
              let readDate = parseISO8601(lastReadAt),
              let messageDate = parseISO8601(lastMessage.createdAt) else {
            return true
        }

        return readDate < messageDate
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yy"
        return formatter
    }()

    private static let threadTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static let timeSeparatorFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d, h:mm a"
        return formatter
    }()

    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
