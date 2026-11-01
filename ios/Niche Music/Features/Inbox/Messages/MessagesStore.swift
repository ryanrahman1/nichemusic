//
//  MessagesStore.swift
//  Niche Music
//

import Foundation
import Combine

@MainActor
final class MessagesStore: ObservableObject {
    @Published private(set) var chats: [ChatPreview] = []
    @Published private(set) var isLoadingInbox = false
    @Published private(set) var inboxError: String?
    @Published private(set) var threadRevision = 0
    @Published private(set) var typingRevision = 0
    @Published var composeIntent: MessageComposeIntent?
    @Published var pendingThreadChat: ChatPreview?

    private let service = MessagesService.shared
    private let realtime = MessagesWebSocketService.shared

    private var selfUserId: String?
    private var inboxRows: [InboxRow] = []
    private var threadStates: [String: ThreadState] = [:]
    private var typingParticipants: [String: [String: TypingParticipant]] = [:]
    private var typingExpiryTasks: [String: Task<Void, Never>] = [:]
    private var outboundTypingState: [String: Bool] = [:]
    private var realtimeHandlerID: UUID?
    private var isSessionActive = false

    struct ThreadState {
        var messages: [ChatMessage] = []
        var apiMessagesById: [String: ConversationMessage] = [:]
        var nextCursor: String?
        var hasMore = false
        var readStates: [ConversationReadState] = []
        var isLoading = false
        var isLoadingOlder = false
    }

    private struct TypingParticipant {
        let userId: String
        let username: String?
        let expiresAt: Date
    }

    private static let typingExpirySeconds: TimeInterval = 5

    func configure(selfUserId: String?) {
        self.selfUserId = selfUserId
    }

    func start() {
        guard selfUserId != nil else { return }

        realtime.setAuthenticated(true)
        if realtimeHandlerID == nil {
            realtimeHandlerID = realtime.addHandler { [weak self] event in
                Task { @MainActor in
                    self?.handleRealtime(event)
                }
            }
        }

        guard !isSessionActive else { return }
        isSessionActive = true

        Task {
            await refreshInbox()
        }
    }

    func reset() {
        isSessionActive = false
        realtime.setAuthenticated(false)
        if let realtimeHandlerID {
            realtime.removeHandler(realtimeHandlerID)
            self.realtimeHandlerID = nil
        }

        selfUserId = nil
        inboxRows = []
        chats = []
        threadStates = [:]
        typingParticipants = [:]
        typingExpiryTasks.values.forEach { $0.cancel() }
        typingExpiryTasks = [:]
        outboundTypingState = [:]
        inboxError = nil
        isLoadingInbox = false
        threadRevision = 0
        typingRevision = 0
        composeIntent = nil
        pendingThreadChat = nil
    }

    func requestCompose() {
        composeIntent = MessageComposeIntent(recipient: nil, conversationId: nil)
    }

    func requestCompose(with recipient: MessageComposeRecipient, conversationId: String? = nil) {
        composeIntent = MessageComposeIntent(recipient: recipient, conversationId: conversationId)
    }

    func chatPreview(
        conversationId: String,
        recipient: MessageComposeRecipient
    ) -> ChatPreview {
        if let existing = chats.first(where: { $0.id == conversationId }) {
            return existing
        }

        return ChatPreview(
            id: conversationId,
            kind: .dm,
            name: recipient.resolvedDisplayName,
            subtitle: "@\(recipient.username)",
            avatarURL: recipient.avatarUrl,
            memberAvatarURLs: [],
            lastMessage: "",
            time: "",
            unreadCount: 0,
            otherUserId: recipient.id,
            otherUsername: recipient.username,
            memberNames: []
        )
    }

    func openConversationFromMatch(
        conversationId: String,
        recipient: MessageComposeRecipient
    ) async {
        await refreshInbox()
        requestCompose(with: recipient, conversationId: conversationId)
    }

    func openConversation(conversationId: String) async {
        await refreshInbox()
        if let chat = chats.first(where: { $0.id == conversationId }) {
            pendingThreadChat = chat
            return
        }

        composeIntent = MessageComposeIntent(recipient: nil, conversationId: conversationId)
    }

    func refreshInbox() async {
        let hasCached = !chats.isEmpty
        if !hasCached {
            isLoadingInbox = true
        }
        inboxError = nil

        do {
            let rows = try await service.fetchInbox()
            inboxRows = sortInbox(rows)
            chats = inboxRows.map { $0.toChatPreview(selfUserId: selfUserId) }
        } catch {
            if !hasCached {
                inboxError = error.localizedDescription
            }
        }

        isLoadingInbox = false
    }

    private func setThreadState(_ conversationId: String, _ state: ThreadState) {
        threadStates[conversationId] = state
        threadRevision &+= 1
    }

    func messages(for conversationId: String) -> [ChatMessage] {
        threadStates[conversationId]?.messages ?? []
    }

    func isLoadingThread(_ conversationId: String) -> Bool {
        threadStates[conversationId]?.isLoading ?? false
    }

    func isLoadingOlderMessages(_ conversationId: String) -> Bool {
        threadStates[conversationId]?.isLoadingOlder ?? false
    }

    func hasMoreMessages(_ conversationId: String) -> Bool {
        threadStates[conversationId]?.hasMore ?? false
    }

    func typingLabel(for chat: ChatPreview) -> String? {
        _ = typingRevision
        let active = activeTypingParticipants(for: chat.id)
        guard !active.isEmpty else { return nil }

        let names = active.map { displayName(for: $0, in: chat) }

        switch names.count {
        case 1:
            return "\(names[0]) is typing..."
        case 2:
            return "\(names[0]) and \(names[1]) are typing..."
        default:
            return "Several people are typing..."
        }
    }

    func isAnyoneTyping(in conversationId: String) -> Bool {
        _ = typingRevision
        return !activeTypingParticipants(for: conversationId).isEmpty
    }

    func setLocalTyping(in conversationId: String, isTyping: Bool) {
        guard outboundTypingState[conversationId] != isTyping else { return }
        outboundTypingState[conversationId] = isTyping
        realtime.sendTyping(conversationId: conversationId, isTyping: isTyping)
    }

    func stopLocalTyping(in conversationId: String) {
        setLocalTyping(in: conversationId, isTyping: false)
    }

    func loadThread(for chat: ChatPreview) async {
        var state = threadStates[chat.id] ?? ThreadState()
        guard !state.isLoading else { return }
        guard state.messages.isEmpty else { return }

        state.isLoading = true
        setThreadState(chat.id, state)

        do {
            let page = try await service.fetchConversation(id: chat.id, cursor: nil, limit: 40)
            state = applyConversationPage(page, to: state, chat: chat)
            state.isLoading = false
            setThreadState(chat.id, state)

            if let latest = page.messages.first {
                try? await service.markRead(conversationId: chat.id, messageId: latest.id)
                applyConversationRead(
                    conversationId: chat.id,
                    userId: selfUserId ?? "",
                    lastReadMessageId: latest.id,
                    lastReadAt: latest.createdAt
                )
                realtime.sendDelivered(conversationId: chat.id, messageId: latest.id)
            }
        } catch {
            state.isLoading = false
            setThreadState(chat.id, state)
        }
    }

    func loadOlderMessages(for chat: ChatPreview) async {
        guard var state = threadStates[chat.id],
              state.hasMore,
              let cursor = state.nextCursor,
              !state.isLoadingOlder,
              !state.isLoading else {
            return
        }

        state.isLoadingOlder = true
        setThreadState(chat.id, state)

        do {
            let page = try await service.fetchConversation(id: chat.id, cursor: cursor, limit: 40)
            state = threadStates[chat.id] ?? state
            let existingIds = Set(state.messages.map(\.id))
            let olderMessages = page.messages
                .reversed()
                .map { mapMessage($0, chat: chat, readStates: state.readStates) }
                .filter { !existingIds.contains($0.id) }

            for message in page.messages where existingIds.contains(message.id) == false {
                state.apiMessagesById[message.id] = message
            }

            state.messages = olderMessages + state.messages
            state.nextCursor = page.nextCursor
            state.hasMore = page.hasMore
            state.messages = remapReadReceipts(in: state.messages, chat: chat, readStates: state.readStates)
            state.isLoadingOlder = false
            setThreadState(chat.id, state)
        } catch {
            state.isLoadingOlder = false
            setThreadState(chat.id, state)
        }
    }

    func sendText(in chat: ChatPreview, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        stopLocalTyping(in: chat.id)

        let clientId = MessagesService.makeClientId()
        let optimistic = ChatMessage(
            id: clientId,
            kind: "text",
            senderId: selfUserId ?? "",
            senderName: "You",
            senderAvatarURL: nil,
            text: trimmed,
            caption: nil,
            isMine: true,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            timestamp: "now",
            isSending: true,
            readReceiptLabel: nil,
            attachment: nil
        )

        var state = threadStates[chat.id] ?? ThreadState()
        state.messages.append(optimistic)
        setThreadState(chat.id, state)

        do {
            let message = try await service.sendTextMessage(
                conversationId: chat.id,
                clientId: clientId,
                text: trimmed
            )

            if var current = threadStates[chat.id] {
                current.apiMessagesById[message.id] = message
                if let index = current.messages.firstIndex(where: { $0.id == clientId }) {
                    current.messages[index] = mapMessage(
                        message,
                        chat: chat,
                        readStates: current.readStates
                    )
                } else {
                    current.messages.append(
                        mapMessage(message, chat: chat, readStates: current.readStates)
                    )
                }
                current.messages = remapReadReceipts(
                    in: current.messages,
                    chat: chat,
                    readStates: current.readStates
                )
                setThreadState(chat.id, current)
            }

            applyMessageCreated(conversationId: chat.id, message: message)
        } catch {
            if var current = threadStates[chat.id] {
                current.messages.removeAll { $0.id == clientId }
                setThreadState(chat.id, current)
            }
        }
    }

    // MARK: – Attachment sends

    func sendTrackShare(
        in chat: ChatPreview,
        appleSourceId: String,
        title: String,
        artistName: String,
        artworkURLString: String?
    ) async {
        let clientId = MessagesService.makeClientId()
        let optimisticAttachment = MessageAttachment(
            id: clientId, kind: .song,
            title: title, subtitle: artistName,
            imageURL: artworkURLString, gifURL: nil, gifWidth: nil, gifHeight: nil,
            username: nil, entityId: nil, source: "apple_music", sourceId: appleSourceId
        )
        insertOptimistic(
            clientId: clientId, kind: "track_share",
            attachment: optimisticAttachment, chat: chat
        )
        do {
            let trackId = try await service.resolveAppleSong(appleSourceId)
            let message = try await service.sendTrackShare(
                conversationId: chat.id, clientId: clientId, trackId: trackId)
            confirmOptimistic(clientId: clientId, message: message, chat: chat)
        } catch {
            removeOptimistic(clientId: clientId, chat: chat)
        }
    }

    func sendAlbumShare(
        in chat: ChatPreview,
        appleSourceId: String,
        title: String,
        artistName: String,
        artworkURLString: String?
    ) async {
        let clientId = MessagesService.makeClientId()
        let optimisticAttachment = MessageAttachment(
            id: clientId, kind: .album,
            title: title, subtitle: artistName,
            imageURL: artworkURLString, gifURL: nil, gifWidth: nil, gifHeight: nil,
            username: nil, entityId: nil, source: "apple_music", sourceId: appleSourceId
        )
        insertOptimistic(
            clientId: clientId, kind: "album_share",
            attachment: optimisticAttachment, chat: chat
        )
        do {
            let albumId = try await service.resolveAppleAlbum(appleSourceId)
            let message = try await service.sendAlbumShare(
                conversationId: chat.id, clientId: clientId, albumId: albumId)
            confirmOptimistic(clientId: clientId, message: message, chat: chat)
        } catch {
            removeOptimistic(clientId: clientId, chat: chat)
        }
    }

    func sendArtistShare(
        in chat: ChatPreview,
        appleSourceId: String,
        name: String,
        imageURLString: String?
    ) async {
        let clientId = MessagesService.makeClientId()
        let optimisticAttachment = MessageAttachment(
            id: clientId, kind: .artist,
            title: name, subtitle: nil,
            imageURL: imageURLString, gifURL: nil, gifWidth: nil, gifHeight: nil,
            username: nil, entityId: nil, source: "apple_music", sourceId: appleSourceId
        )
        insertOptimistic(
            clientId: clientId, kind: "artist_share",
            attachment: optimisticAttachment, chat: chat
        )
        do {
            let artistId = try await service.resolveAppleArtist(appleSourceId)
            let message = try await service.sendArtistShare(
                conversationId: chat.id, clientId: clientId, artistId: artistId)
            confirmOptimistic(clientId: clientId, message: message, chat: chat)
        } catch {
            removeOptimistic(clientId: clientId, chat: chat)
        }
    }

    func sendProfileShare(
        in chat: ChatPreview,
        userId: String,
        username: String,
        displayName: String?,
        avatarURLString: String?
    ) async {
        let clientId = MessagesService.makeClientId()
        let title = displayName ?? username
        let optimisticAttachment = MessageAttachment(
            id: clientId, kind: .profile,
            title: title, subtitle: "@\(username)",
            imageURL: avatarURLString, gifURL: nil, gifWidth: nil, gifHeight: nil,
            username: username, entityId: userId, source: nil, sourceId: nil
        )
        insertOptimistic(
            clientId: clientId, kind: "profile_share",
            attachment: optimisticAttachment, chat: chat
        )
        do {
            let message = try await service.sendProfileShare(
                conversationId: chat.id, clientId: clientId, userId: userId)
            confirmOptimistic(clientId: clientId, message: message, chat: chat)
        } catch {
            removeOptimistic(clientId: clientId, chat: chat)
        }
    }

    func sendGif(
        in chat: ChatPreview,
        url: String,
        width: Int,
        height: Int
    ) async {
        let clientId = MessagesService.makeClientId()
        let optimisticAttachment = MessageAttachment(
            id: clientId, kind: .gif,
            title: "GIF", subtitle: nil,
            imageURL: nil, gifURL: url, gifWidth: width, gifHeight: height,
            username: nil, entityId: nil, source: nil, sourceId: nil
        )
        insertOptimistic(
            clientId: clientId, kind: "gif",
            attachment: optimisticAttachment, chat: chat
        )
        do {
            let message = try await service.sendGif(
                conversationId: chat.id, clientId: clientId,
                gifUrl: url, width: width, height: height)
            confirmOptimistic(clientId: clientId, message: message, chat: chat)
        } catch {
            removeOptimistic(clientId: clientId, chat: chat)
        }
    }

    // MARK: – Optimistic helpers

    private func insertOptimistic(
        clientId: String,
        kind: String,
        attachment: MessageAttachment?,
        chat: ChatPreview
    ) {
        let optimistic = ChatMessage(
            id: clientId,
            kind: kind,
            senderId: selfUserId ?? "",
            senderName: "You",
            senderAvatarURL: nil,
            text: nil,
            caption: nil,
            isMine: true,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            timestamp: "now",
            isSending: true,
            readReceiptLabel: nil,
            attachment: attachment
        )
        var state = threadStates[chat.id] ?? ThreadState()
        state.messages.append(optimistic)
        setThreadState(chat.id, state)
    }

    private func confirmOptimistic(
        clientId: String,
        message: ConversationMessage,
        chat: ChatPreview
    ) {
        if var current = threadStates[chat.id] {
            current.apiMessagesById[message.id] = message
            let mapped = mapMessage(message, chat: chat, readStates: current.readStates)
            if let index = current.messages.firstIndex(where: { $0.id == clientId }) {
                current.messages[index] = mapped
            } else {
                current.messages.append(mapped)
            }
            current.messages = remapReadReceipts(
                in: current.messages, chat: chat, readStates: current.readStates)
            setThreadState(chat.id, current)
        }
        applyMessageCreated(conversationId: chat.id, message: message)
    }

    private func removeOptimistic(clientId: String, chat: ChatPreview) {
        if var current = threadStates[chat.id] {
            current.messages.removeAll { $0.id == clientId }
            setThreadState(chat.id, current)
        }
    }

    private func handleRealtime(_ event: MessagesRealtimeEvent) {
        switch event {
        case .messageCreated(let conversationId, let payload):
            if let message = decodeConversationMessage(payload) {
                clearTypingUser(conversationId: conversationId, userId: message.senderId)
                applyMessageCreated(conversationId: conversationId, message: message)

                if var state = threadStates[conversationId] {
                    let chat = chats.first(where: { $0.id == conversationId })
                    let mapped = mapMessage(
                        message,
                        chat: chat ?? ChatPreview.placeholder(id: conversationId),
                        readStates: state.readStates
                    )

                    if !state.messages.contains(where: { $0.id == mapped.id }) {
                        state.apiMessagesById[message.id] = message
                        state.messages.append(mapped)
                        state.messages = remapReadReceipts(
                            in: state.messages,
                            chat: chat ?? ChatPreview.placeholder(id: conversationId),
                            readStates: state.readStates
                        )
                        setThreadState(conversationId, state)
                    }

                    if message.senderId != selfUserId {
                        realtime.sendDelivered(conversationId: conversationId, messageId: message.id)
                    }
                } else if message.senderId != selfUserId {
                    Task { await refreshInbox() }
                }
            } else {
                Task { await refreshInbox() }
            }

        case .messageUnsent:
            Task { await refreshInbox() }

        case .conversationRead(let conversationId, let userId, let lastReadMessageId, let lastReadAt):
            applyConversationRead(
                conversationId: conversationId,
                userId: userId,
                lastReadMessageId: lastReadMessageId,
                lastReadAt: lastReadAt
            )
            updateThreadReadState(
                conversationId: conversationId,
                userId: userId,
                lastReadMessageId: lastReadMessageId,
                lastReadAt: lastReadAt
            )

        case .typing(let conversationId, let userId, let username, let isTyping):
            applyTyping(
                conversationId: conversationId,
                userId: userId,
                username: username,
                isTyping: isTyping
            )

        case .messageDelivered:
            break
        }
    }

    private func applyTyping(
        conversationId: String,
        userId: String,
        username: String?,
        isTyping: Bool
    ) {
        guard userId != selfUserId else { return }

        let taskKey = "\(conversationId):\(userId)"

        if isTyping {
            typingParticipants[conversationId, default: [:]][userId] = TypingParticipant(
                userId: userId,
                username: username,
                expiresAt: Date().addingTimeInterval(Self.typingExpirySeconds)
            )

            typingExpiryTasks[taskKey]?.cancel()
            typingExpiryTasks[taskKey] = Task { [weak self] in
                try? await Task.sleep(
                    nanoseconds: UInt64(Self.typingExpirySeconds * 1_000_000_000)
                )
                await MainActor.run {
                    self?.clearTypingUser(conversationId: conversationId, userId: userId)
                }
            }
        } else {
            clearTypingUser(conversationId: conversationId, userId: userId)
            return
        }

        typingRevision &+= 1
    }

    private func clearTypingUser(conversationId: String, userId: String) {
        let taskKey = "\(conversationId):\(userId)"
        typingExpiryTasks[taskKey]?.cancel()
        typingExpiryTasks.removeValue(forKey: taskKey)

        guard var participants = typingParticipants[conversationId] else { return }
        guard participants.removeValue(forKey: userId) != nil else { return }

        if participants.isEmpty {
            typingParticipants.removeValue(forKey: conversationId)
        } else {
            typingParticipants[conversationId] = participants
        }

        typingRevision &+= 1
    }

    private func activeTypingParticipants(for conversationId: String) -> [TypingParticipant] {
        let now = Date()
        let participants = typingParticipants[conversationId] ?? [:]
        return participants.values
            .filter { $0.expiresAt > now }
            .sorted { lhs, rhs in
                displayName(for: lhs, in: nil).localizedCaseInsensitiveCompare(
                    displayName(for: rhs, in: nil)
                ) == .orderedAscending
            }
    }

    private func displayName(for participant: TypingParticipant, in chat: ChatPreview?) -> String {
        if let chat, chat.kind == .dm {
            return chat.name
        }

        if let username = participant.username, !username.isEmpty {
            return username
        }

        if let chat,
           let memberName = chat.memberNames.first(where: { !$0.isEmpty }) {
            return memberName
        }

        return "Someone"
    }

    private func applyMessageCreated(conversationId: String, message: ConversationMessage) {
        guard let index = inboxRows.firstIndex(where: { $0.id == conversationId }) else {
            Task { await refreshInbox() }
            return
        }

        inboxRows[index] = inboxRows[index].updating(
            lastMessageAt: message.createdAt,
            lastMessage: InboxLastMessage(
                id: message.id,
                conversationId: message.conversationId,
                senderId: message.senderId,
                kind: message.kind,
                createdAt: message.createdAt,
                textPlain: message.textPlain,
                content: message.content
            )
        )
        inboxRows = sortInbox(inboxRows)
        chats = inboxRows.map { $0.toChatPreview(selfUserId: selfUserId) }
    }

    private func applyConversationRead(
        conversationId: String,
        userId: String,
        lastReadMessageId: String,
        lastReadAt: String
    ) {
        guard userId == selfUserId,
              let index = inboxRows.firstIndex(where: { $0.id == conversationId }) else {
            return
        }

        inboxRows[index] = inboxRows[index].updating(
            lastReadMessageId: lastReadMessageId,
            lastReadAt: lastReadAt
        )
        chats = inboxRows.map { $0.toChatPreview(selfUserId: selfUserId) }
    }

    private func updateThreadReadState(
        conversationId: String,
        userId: String,
        lastReadMessageId: String,
        lastReadAt: String
    ) {
        guard var state = threadStates[conversationId],
              let chat = chats.first(where: { $0.id == conversationId }) else {
            return
        }

        if let index = state.readStates.firstIndex(where: { $0.userId == userId }) {
            state.readStates[index] = ConversationReadState(
                userId: userId,
                lastReadMessageId: lastReadMessageId,
                lastReadAt: lastReadAt
            )
        } else {
            state.readStates.append(
                ConversationReadState(
                    userId: userId,
                    lastReadMessageId: lastReadMessageId,
                    lastReadAt: lastReadAt
                )
            )
        }

        state.messages = remapReadReceipts(
            in: state.messages,
            chat: chat,
            readStates: state.readStates
        )

        setThreadState(conversationId, state)
    }

    private func applyConversationPage(
        _ page: ConversationPageResponse,
        to state: ThreadState,
        chat: ChatPreview
    ) -> ThreadState {
        var updated = state
        updated.apiMessagesById.merge(
            Dictionary(uniqueKeysWithValues: page.messages.map { ($0.id, $0) })
        ) { _, new in new }
        updated.messages = page.messages
            .reversed()
            .map { mapMessage($0, chat: chat, readStates: page.readStates) }
        updated.nextCursor = page.nextCursor
        updated.hasMore = page.hasMore
        updated.readStates = page.readStates
        return updated
    }

    private func remapReadReceipts(
        in messages: [ChatMessage],
        chat: ChatPreview,
        readStates: [ConversationReadState]
    ) -> [ChatMessage] {
        let peerState = chat.kind == .dm
            ? readStates.first(where: { $0.userId == chat.otherUserId })
            : nil

        return messages.map { message in
            let label = readReceiptLabel(
                for: message,
                chat: chat,
                peerLastReadMessageId: peerState?.lastReadMessageId,
                peerLastReadAt: peerState?.lastReadAt
            )

            return ChatMessage(
                id: message.id,
                kind: message.kind,
                senderId: message.senderId,
                senderName: message.senderName,
                senderAvatarURL: message.senderAvatarURL,
                text: message.text,
                caption: message.caption,
                isMine: message.isMine,
                createdAt: message.createdAt,
                timestamp: message.timestamp,
                isSending: message.isSending,
                readReceiptLabel: label,
                attachment: message.attachment
            )
        }
    }

    private func sortInbox(_ rows: [InboxRow]) -> [InboxRow] {
        rows.sorted {
            let left = parseDate($0.lastMessageAt) ?? parseDate($0.createdAt) ?? .distantPast
            let right = parseDate($1.lastMessageAt) ?? parseDate($1.createdAt) ?? .distantPast
            return left > right
        }
    }

    private func mapMessage(
        _ message: ConversationMessage,
        chat: ChatPreview,
        readStates: [ConversationReadState]
    ) -> ChatMessage {
        let isMine = message.senderId == selfUserId
        let senderName = message.sender?.displayName
            ?? message.sender?.username
            ?? (isMine ? "You" : chat.name)
        let peerState = chat.kind == .dm
            ? readStates.first(where: { $0.userId == chat.otherUserId })
            : nil
        let mapped = ChatMessage(
            id: message.id,
            kind: message.kind,
            senderId: message.senderId,
            senderName: senderName,
            senderAvatarURL: message.sender?.avatarUrl,
            text: threadText(for: message),
            caption: threadCaption(for: message),
            isMine: isMine,
            createdAt: message.createdAt,
            timestamp: MessagesFormatting.threadTimestamp(message.createdAt),
            isSending: false,
            readReceiptLabel: readReceiptLabel(
                forMessageId: message.id,
                isMine: isMine,
                chat: chat,
                peerLastReadMessageId: peerState?.lastReadMessageId,
                peerLastReadAt: peerState?.lastReadAt
            ),
            attachment: mapAttachment(for: message)
        )
        return mapped
    }

    private func readReceiptLabel(
        for message: ChatMessage,
        chat: ChatPreview,
        peerLastReadMessageId: String?,
        peerLastReadAt: String?
    ) -> String? {
        readReceiptLabel(
            forMessageId: message.id,
            isMine: message.isMine,
            chat: chat,
            peerLastReadMessageId: peerLastReadMessageId,
            peerLastReadAt: peerLastReadAt
        )
    }

    private func readReceiptLabel(
        forMessageId messageId: String,
        isMine: Bool,
        chat: ChatPreview,
        peerLastReadMessageId: String?,
        peerLastReadAt: String?
    ) -> String? {
        guard isMine, chat.kind == .dm, peerLastReadMessageId == messageId else {
            return nil
        }

        if let peerLastReadAt, MessagesFormatting.readReceiptTime(peerLastReadAt) != nil {
            return "Read at \(MessagesFormatting.readReceiptTime(peerLastReadAt)!)"
        }

        return "Seen"
    }

    private func threadText(for message: ConversationMessage) -> String? {
        guard message.kind == "text" else { return nil }

        if let plain = message.textPlain?.trimmingCharacters(in: .whitespacesAndNewlines), !plain.isEmpty {
            return plain
        }

        if let text = message.content?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }

        return nil
    }

    private func threadCaption(for message: ConversationMessage) -> String? {
        guard message.kind != "text" else { return nil }

        if let caption = message.content?.caption?.trimmingCharacters(in: .whitespacesAndNewlines),
           !caption.isEmpty {
            return caption
        }

        if let plain = message.textPlain?.trimmingCharacters(in: .whitespacesAndNewlines),
           !plain.isEmpty {
            return plain
        }

        return nil
    }

    private func mapAttachment(for message: ConversationMessage) -> MessageAttachment? {
        switch message.kind {
        case "track_share":
            return MessageAttachment(
                id: message.id,
                kind: .song,
                title: message.entity?.name ?? "Track",
                subtitle: message.entity?.artists?.name,
                imageURL: message.entity?.artworkUrl,
                gifURL: nil,
                gifWidth: nil,
                gifHeight: nil,
                username: nil,
                entityId: message.entity?.id,
                source: message.entity?.source,
                sourceId: message.entity?.sourceId
            )

        case "album_share":
            return MessageAttachment(
                id: message.id,
                kind: .album,
                title: message.entity?.name ?? "Album",
                subtitle: message.entity?.artists?.name,
                imageURL: message.entity?.artworkUrl,
                gifURL: nil,
                gifWidth: nil,
                gifHeight: nil,
                username: nil,
                entityId: message.entity?.id,
                source: message.entity?.source,
                sourceId: message.entity?.sourceId
            )

        case "artist_share":
            return MessageAttachment(
                id: message.id,
                kind: .artist,
                title: message.entity?.name ?? "Artist",
                subtitle: nil,
                imageURL: message.entity?.imageUrl,
                gifURL: nil,
                gifWidth: nil,
                gifHeight: nil,
                username: nil,
                entityId: message.entity?.id,
                source: message.entity?.source,
                sourceId: message.entity?.sourceId
            )

        case "profile_share":
            let username = message.entity?.username ?? ""
            return MessageAttachment(
                id: message.id,
                kind: .profile,
                title: message.entity?.displayName ?? (username.isEmpty ? "Profile" : username),
                subtitle: username.isEmpty ? nil : "@\(username)",
                imageURL: message.entity?.avatarUrl,
                gifURL: nil,
                gifWidth: nil,
                gifHeight: nil,
                username: username.isEmpty ? nil : username,
                entityId: message.entity?.id,
                source: nil,
                sourceId: nil
            )

        case "gif":
            return MessageAttachment(
                id: message.id,
                kind: .gif,
                title: "GIF",
                subtitle: nil,
                imageURL: nil,
                gifURL: message.content?.gifUrl,
                gifWidth: message.content?.width,
                gifHeight: message.content?.height,
                username: nil,
                entityId: nil,
                source: nil,
                sourceId: nil
            )

        default:
            return nil
        }
    }

    private func decodeConversationMessage(_ payload: [String: Any]) -> ConversationMessage? {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(ConversationMessage.self, from: data)
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private extension InboxRow {
    func toChatPreview(selfUserId: String?) -> ChatPreview {
        let kind: ChatKind = conversationType == "group" ? .group : .dm

        let name: String
        let subtitle: String
        let avatarURL: String?

        if kind == .group {
            name = title ?? "Group"
            let count = members?.count ?? 0
            subtitle = count == 1 ? "1 member" : "\(count) members"
            avatarURL = nil
        } else {
            name = otherUser?.displayName ?? otherUser?.username ?? "Chat"
            subtitle = otherUser.map { "@\($0.username)" } ?? ""
            avatarURL = otherUser?.avatarUrl
        }

        let unread = MessagesFormatting.hasUnread(selfUserId: selfUserId, row: self) ? 1 : 0

        return ChatPreview(
            id: id,
            kind: kind,
            name: name,
            subtitle: subtitle,
            avatarURL: avatarURL,
            memberAvatarURLs: members?.compactMap(\.avatarUrl) ?? [],
            lastMessage: MessagesFormatting.previewLine(for: lastMessage),
            time: MessagesFormatting.shortRelativeTime(lastMessageAt ?? lastMessage?.createdAt) ?? "",
            unreadCount: unread,
            otherUserId: otherUser?.id,
            otherUsername: otherUser?.username,
            memberNames: members?.map { $0.displayName ?? $0.username } ?? []
        )
    }
}

private extension ChatPreview {
    static func placeholder(id: String) -> ChatPreview {
        ChatPreview(
            id: id,
            kind: .dm,
            name: "Chat",
            subtitle: "",
            avatarURL: nil,
            memberAvatarURLs: [],
            lastMessage: "",
            time: "",
            unreadCount: 0,
            otherUserId: nil,
            otherUsername: nil,
            memberNames: []
        )
    }
}
