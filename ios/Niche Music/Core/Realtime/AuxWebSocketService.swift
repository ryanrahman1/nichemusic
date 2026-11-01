//
//  AuxWebSocketService.swift
//  Niche Music
//

import Foundation

enum AuxRealtimeEvent {
    case joined([String: Any])
    case error(code: String)
    case message([String: Any])
    case disconnected
}

@MainActor
final class AuxWebSocketService {
    private var webSocketTask: URLSessionWebSocketTask?
    private var heartbeatTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private var roomId: String?
    private var onEvent: ((AuxRealtimeEvent) -> Void)?

    private let heartbeatInterval: TimeInterval = 25
    private let reconnectBase: TimeInterval = 1
    private let reconnectMax: TimeInterval = 10

    func connect(roomId: String, onEvent: @escaping (AuxRealtimeEvent) -> Void) {
        self.roomId = roomId
        self.onEvent = onEvent
        reconnectAttempts = 0
        openConnection(sendJoin: true)
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        reconnectAttempts = 0
        roomId = nil
        onEvent = nil

        if webSocketTask != nil {
            sendJSON(["type": "leave"])
        }
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    private func openConnection(sendJoin: Bool) {
        reconnectTask?.cancel()
        reconnectTask = nil

        if let webSocketTask {
            switch webSocketTask.state {
            case .running, .suspended:
                if sendJoin, let roomId {
                    sendJSON(["type": "join", "roomId": roomId])
                }
                return
            case .canceling, .completed:
                break
            @unknown default:
                break
            }
        }

        guard let url = APIClient.shared.auxWebSocketURL else { return }

        let task = URLSession.shared.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        startReceiveLoop()
        startHeartbeat()

        if sendJoin, let roomId {
            sendJSON(["type": "join", "roomId": roomId])
        }
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
                onEvent?(.disconnected)
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

        switch type {
        case "aux.joined":
            onEvent?(.joined(json))
        case "aux.error":
            let code = json["code"] as? String ?? "UNKNOWN"
            if code == "NOT_IN_ROOM", let roomId {
                sendJSON(["type": "join", "roomId": roomId])
            } else {
                onEvent?(.error(code: code))
            }
        default:
            onEvent?(.message(json))
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

        guard roomId != nil else { return }

        reconnectTask?.cancel()
        let delay = min(reconnectBase * pow(2, Double(reconnectAttempts)), reconnectMax)
        reconnectAttempts += 1

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self?.openConnection(sendJoin: true)
        }
    }
}
