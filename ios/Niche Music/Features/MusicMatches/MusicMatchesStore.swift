//
//  MusicMatchesStore.swift
//  Niche Music
//

import Foundation
import Combine

enum MatchRespondResult: Equatable {
    case mutualAccept(conversationId: String)
    case waitingForOther
    case rejectedByOther
    case alreadyInactive
    case failed
}

@MainActor
final class MusicMatchesStore: ObservableObject {
    @Published var pendingMatch: MusicMatch?
    @Published private(set) var isResponding = false

    private var didCheckThisLaunch = false
    private var launchCheckTask: Task<Void, Never>?
    private let api = APIClient.shared
    private let launchDelay: Duration = .seconds(15)

    func scheduleLaunchCheck() {
        guard !didCheckThisLaunch else { return }
        guard launchCheckTask == nil else { return }

        launchCheckTask = Task {
            try? await Task.sleep(for: launchDelay)
            guard !Task.isCancelled else { return }
            await performLaunchCheck()
        }
    }

    func resetForNewLaunch() {
        launchCheckTask?.cancel()
        launchCheckTask = nil
        didCheckThisLaunch = false
        pendingMatch = nil
        isResponding = false
    }

    private func performLaunchCheck() async {
        guard !didCheckThisLaunch else { return }
        didCheckThisLaunch = true

        do {
            let response: MusicMatchCheckResponse = try await api.request(
                Endpoints.musicMatchesCheck,
                method: .get
            )
            pendingMatch = Self.actionableMatch(from: response.match)
        } catch {
            // no match UI on failure
        }
    }

    private static func actionableMatch(from match: MusicMatch?) -> MusicMatch? {
        guard let match else { return nil }
        guard match.status == "pending", !match.viewerHasResponded else { return nil }
        return match
    }

    func clearPendingMatch() {
        pendingMatch = nil
    }

    func fetchLatestMatch() async -> MusicMatch? {
        do {
            let response: MusicMatchCheckResponse = try await api.request(
                Endpoints.musicMatchesLatest,
                method: .get
            )
            return response.match
        } catch {
            return nil
        }
    }

    @discardableResult
    func acceptMatch(_ match: MusicMatch) async -> MatchRespondResult {
        await respond(match: match, action: "accept")
    }

    func declineMatch(_ match: MusicMatch) async {
        _ = await respond(match: match, action: "decline")
    }

    @discardableResult
    private func respond(match: MusicMatch, action: String) async -> MatchRespondResult {
        isResponding = true
        defer { isResponding = false }

        do {
            let response: MusicMatchRespondResponse = try await api.request(
                Endpoints.musicMatchRespond(id: match.id),
                method: .post,
                body: MusicMatchRespondBody(action: action)
            )
            if pendingMatch?.id == match.id {
                pendingMatch = nil
            }
            if action == "decline" {
                return .alreadyInactive
            }
            if response.accepted == true, let conversation = response.conversation {
                return .mutualAccept(conversationId: conversation.id)
            }
            return .waitingForOther
        } catch let error as APIClientError {
            if pendingMatch?.id == match.id {
                pendingMatch = nil
            }
            if case .server(_, let payload) = error {
                switch payload?.code {
                case "MATCH_NOT_PENDING":
                    if match.declinedByOther {
                        return .rejectedByOther
                    }
                    return .alreadyInactive
                default:
                    break
                }
            }
            return .failed
        } catch {
            if pendingMatch?.id == match.id {
                pendingMatch = nil
            }
            return .failed
        }
    }
}
