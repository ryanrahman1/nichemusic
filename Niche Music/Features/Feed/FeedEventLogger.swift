//
//  FeedEventLogger.swift
//  Niche Music
//

import Foundation

enum FeedEntityType: String, Encodable {
    case post
    case track
    case album
    case artist
    case profile
    case feedItem = "feed_item"
}

private struct FeedEntityEventBody: Encodable {
    let entityType: FeedEntityType
    let entityId: String
}

private struct FeedViewEventBody: Encodable {
    let entityType: FeedEntityType
    let entityId: String
    let watchTimeMs: Int?
}

private struct FeedSkipEventBody: Encodable {
    let entityType: FeedEntityType
    let entityId: String
    let watchTimeMs: Int?
}

private struct FeedOpenProfileBody: Encodable {
    let profileId: String
}

@MainActor
final class FeedEventLogger {
    static let shared = FeedEventLogger()

    private let api = APIClient.shared
    private let impressionDelay: Duration = .seconds(1.5)

    private var loggedImpressions = Set<String>()
    private var pendingImpressionTask: Task<Void, Never>?
    private var pendingImpressionPostId: String?

    private init() {}

    // MARK: - Impression scheduling

    func scheduleImpression(postId: String) {
        cancelPendingImpression()

        guard !loggedImpressions.contains(postId) else { return }

        pendingImpressionPostId = postId
        pendingImpressionTask = Task {
            try? await Task.sleep(for: impressionDelay)
            guard !Task.isCancelled, pendingImpressionPostId == postId else { return }
            await logImpression(postId: postId)
        }
    }

    func cancelPendingImpression() {
        pendingImpressionTask?.cancel()
        pendingImpressionTask = nil
        pendingImpressionPostId = nil
    }

    // MARK: - Events

    func logImpression(postId: String) async {
        guard !loggedImpressions.contains(postId) else { return }
        loggedImpressions.insert(postId)

        do {
            try await api.requestVoid(
                Endpoints.feedImpression,
                method: .post,
                body: FeedEntityEventBody(entityType: .post, entityId: postId),
                preserveBodyKeyNames: true
            )
        } catch {
            loggedImpressions.remove(postId)
            print("Failed to log impression:", error)
        }
    }

    func logView(
        entityType: FeedEntityType,
        entityId: String,
        watchTimeMs: Int? = nil
    ) async {
        do {
            try await api.requestVoid(
                Endpoints.feedView,
                method: .post,
                body: FeedViewEventBody(
                    entityType: entityType,
                    entityId: entityId,
                    watchTimeMs: watchTimeMs
                ),
                preserveBodyKeyNames: true
            )
        } catch {
            print("Failed to log view:", error)
        }
    }

    func logSkip(
        entityType: FeedEntityType,
        entityId: String,
        watchTimeMs: Int? = nil
    ) async {
        do {
            try await api.requestVoid(
                Endpoints.feedSkip,
                method: .post,
                body: FeedSkipEventBody(
                    entityType: entityType,
                    entityId: entityId,
                    watchTimeMs: watchTimeMs
                ),
                preserveBodyKeyNames: true
            )
        } catch {
            print("Failed to log skip:", error)
        }
    }

    func logProfileOpen(profileId: String) async {
        do {
            try await api.requestVoid(
                Endpoints.feedOpenProfile,
                method: .post,
                body: FeedOpenProfileBody(profileId: profileId),
                preserveBodyKeyNames: true
            )
        } catch {
            print("Failed to log profile open:", error)
        }
    }
}
