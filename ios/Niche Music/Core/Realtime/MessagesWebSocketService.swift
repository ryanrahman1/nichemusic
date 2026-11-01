//
//  MessagesWebSocketService.swift
//  Niche Music
//

import Foundation

enum MessagesRealtimeEvent {
    case messageCreated(conversationId: String, message: [String: Any])
    case messageUnsent
    case conversationRead(
        conversationId: String,
        userId: String,
        lastReadMessageId: String,
        lastReadAt: String
    )
    case typing(conversationId: String, userId: String, username: String?, isTyping: Bool)
    case messageDelivered(conversationId: String, messageId: String)
}

@MainActor
final class MessagesWebSocketService {
    static let shared = MessagesWebSocketService()

    private var webSocketTask: URLSessionWebSocketTask?
    private var heartbeatTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private var isAuthenticated = false
    private var handlers: [UUID: (MessagesRealtimeEvent) -> Void] = [:]

    private let heartbeatInterval: TimeInterval = 25
    private let reconnectBase: TimeInterval = 1
    private let reconnectMax: TimeInterval = 10

    private init() {}

    func setAuthenticated(_ value: Bool) {
        isAuthenticated = value
        if value {
            connectIfNeeded()
        } else {
            disconnect()
        }
    }

    @discardableResult
    func addHandler(_ handler: @escaping (MessagesRealtimeEvent) -> Void) -> UUID {
        let id = UUID()
        handlers[id] = handler
        return id
    }

    func removeHandler(_ id: UUID) {
        handlers.removeValue(forKey: id)
    }

    func sendTyping(conversationId: String, isTyping: Bool) {
        sendJSON([
            "type": "typing",
            "conversationId": conversationId,
            "isTyping": isTyping,
        ])
    }

    func sendDelivered(conversationId: String, messageId: String) {
        sendJSON([
            "type": "message.delivered",
            "conversationId": conversationId,
            "messageId": messageId,
        ])
    }

    private func connectIfNeeded() {
        guard isAuthenticated else { return }

        if let webSocketTask {
            switch webSocketTask.state {
            case .running, .suspended:
                return
            case .canceling, .completed:
                break
            @unknown default:
                break
            }
        }

        reconnectTask?.cancel()
        reconnectTask = nil

        guard let url = APIClient.shared.websocketURL else { return }

        let task = URLSession.shared.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        startReceiveLoop()
        startHeartbeat()
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        reconnectAttempts = 0

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64((self?.heartbeatInterval ?? 25) * 1_000_000_000))
                self?.sendJSON([
                    "type": "ping",
                    "ts": Int(Date().timeIntervalSince1970 * 1000),
                ])
            }
        }
    }

    private func startReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    private func receiveLoop() async {
        guard let webSocketTask else { return }

        while !Task.isCancelled {
            do {
                let message = try await webSocketTask.receive()
                switch message {
                case .string(let text):
                    handleIncoming(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleIncoming(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                scheduleReconnect()
                return
            }
        }
    }

    private func handleIncoming(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        if type == "pong" { return }

        let event: MessagesRealtimeEvent?
        switch type {
        case "message_created":
            guard let conversationId = json["conversationId"] as? String,
                  let msg = json["msg"] as? [String: Any] else {
                event = nil
                break
            }
            event = .messageCreated(conversationId: conversationId, message: msg)

        case "message_unsent":
            event = .messageUnsent

        case "conversation.read":
            guard let conversationId = json["conversationId"] as? String,
                  let userId = json["userId"] as? String else {
                event = nil
                break
            }
            let messageId = (json["lastReadMessageId"] as? String)
                ?? (json["lastReadmessageId"] as? String)
            let readAt = json["lastReadAt"] as? String
            if let messageId, let readAt {
                event = .conversationRead(
                    conversationId: conversationId,
                    userId: userId,
                    lastReadMessageId: messageId,
                    lastReadAt: readAt
                )
            } else {
                event = nil
            }

        case "typing":
            guard let conversationId = json["conversationId"] as? String,
                  let userId = json["userId"] as? String,
                  let isTyping = json["isTyping"] as? Bool else {
                event = nil
                break
            }
            let username = json["username"] as? String
            event = .typing(
                conversationId: conversationId,
                userId: userId,
                username: username,
                isTyping: isTyping
            )

        case "message.delivered":
            guard let conversationId = json["conversationId"] as? String,
                  let messageId = json["messageId"] as? String else {
                event = nil
                break
            }
            event = .messageDelivered(conversationId: conversationId, messageId: messageId)

        default:
            event = nil
        }

        guard let event else { return }
        for handler in handlers.values {
            handler(event)
        }
    }

    private func sendJSON(_ payload: [String: Any]) {
        guard let webSocketTask,
              webSocketTask.state == .running,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        webSocketTask.send(.string(text)) { _ in }
    }

    private func scheduleReconnect() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask = nil

        guard isAuthenticated else { return }

        reconnectTask?.cancel()
        let delay = min(reconnectBase * pow(2, Double(reconnectAttempts)), reconnectMax)
        reconnectAttempts += 1

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self?.connectIfNeeded()
        }
    }
}
