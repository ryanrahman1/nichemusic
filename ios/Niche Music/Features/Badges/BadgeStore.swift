//
//  BadgeStore.swift
//  Niche Music
//

import Foundation
import Combine

@MainActor
final class BadgeStore: ObservableObject {
    @Published private(set) var badge: BadgeDetail?
    @Published private(set) var holders: [BadgeHolder] = []
    @Published private(set) var isLoadingBadge = false
    @Published private(set) var isLoadingHolders = false
    @Published private(set) var isLoadingMoreHolders = false
    @Published private(set) var errorMessage: String?

    private let badgeId: String
    private let api = APIClient.shared
    private let pageSize = 30
    private var nextCursor: String?
    private var hasMore = false

    init(badgeId: String) {
        self.badgeId = badgeId
    }

    func load(initialPreview: BadgeDetail? = nil) async {
        if let initialPreview, badge == nil {
            badge = initialPreview
        }

        async let badgeTask: Void = loadBadge(force: true)
        async let holdersTask: Void = loadHolders(reset: true)
        _ = await (badgeTask, holdersTask)
    }

    func refresh() async {
        async let badgeTask: Void = loadBadge(force: true)
        async let holdersTask: Void = loadHolders(reset: true)
        _ = await (badgeTask, holdersTask)
    }

    func loadMoreIfNeeded(currentHolder holder: BadgeHolder) async {
        guard hasMore, !isLoadingHolders, !isLoadingMoreHolders else { return }
        guard holder.id == holders.last?.id else { return }
        await loadHolders(reset: false)
    }

    private func loadBadge(force: Bool) async {
        if isLoadingBadge { return }
        if badge != nil, !force { return }

        isLoadingBadge = true
        if badge == nil {
            errorMessage = nil
        }

        do {
            let response: BadgeDetailResponse = try await api.request(
                Endpoints.badge(id: badgeId),
                method: .get
            )
            badge = response.badge
        } catch {
            if badge == nil {
                errorMessage = error.localizedDescription
            }
        }

        isLoadingBadge = false
    }

    private func loadHolders(reset: Bool) async {
        if reset {
            if isLoadingHolders { return }
            isLoadingHolders = true
            nextCursor = nil
            hasMore = false
        } else {
            if isLoadingMoreHolders { return }
            isLoadingMoreHolders = true
        }

        if reset {
            errorMessage = nil
        }

        do {
            let query: [String: String?] = [
                "limit": String(pageSize),
                "cursor": reset ? nil : nextCursor,
            ]

            let response: (result: BadgeHoldersResponse, metadata: APIMetadata?) =
                try await api.requestWithMetadata(
                    Endpoints.badgeHolders(badgeId: badgeId),
                    method: .get,
                    query: query
                )

            if reset {
                holders = response.result.holders
            } else {
                let existingIds = Set(holders.map(\.id))
                let newRows = response.result.holders.filter { !existingIds.contains($0.id) }
                holders.append(contentsOf: newRows)
            }

            nextCursor = response.metadata?.pagination?.nextCursor
            hasMore = response.metadata?.pagination?.hasMore ?? false

            if reset {
                errorMessage = nil
            }
        } catch {
            if reset, holders.isEmpty {
                errorMessage = error.localizedDescription
            }
        }

        if reset {
            isLoadingHolders = false
        } else {
            isLoadingMoreHolders = false
        }
    }
}
