//
//  PlaylistStore.swift
//  Niche Music
//

import Foundation
import Combine

@MainActor
final class PlaylistStore: ObservableObject {
    @Published private(set) var myPlaylists: [PlaylistSummary] = []
    @Published private(set) var isLoadingMyPlaylists = false
    @Published private(set) var isLoadingMoreMyPlaylists = false
    @Published private(set) var myPlaylistsError: String?
    @Published private(set) var myPlaylistsHasMore = false

    @Published private(set) var userPlaylistsByUsername: [String: [PlaylistSummary]] = [:]
    @Published private(set) var isLoadingUserPlaylistsByUsername: Set<String> = []
    @Published private(set) var isLoadingMoreUserPlaylistsByUsername: Set<String> = []
    @Published private(set) var userPlaylistsErrorByUsername: [String: String] = [:]
    @Published private(set) var userPlaylistsHasMoreByUsername: [String: Bool] = [:]

    @Published private(set) var detailsById: [String: PlaylistDetail] = [:]
    @Published private(set) var loadingDetailIds: Set<String> = []
    @Published private(set) var loadingMoreDetailIds: Set<String> = []
    @Published private(set) var detailErrorsById: [String: String] = [:]

    @Published private(set) var trackMembershipsByTrackId: [String: [PlaylistTrackMembership]] = [:]
    @Published private(set) var loadingTrackMembershipIds: Set<String> = []

    private let api = APIClient.shared
    private let pageSize = 30
    private let ttl: TimeInterval = 120

    private var myPlaylistsNextCursor: String?
    private var myPlaylistsLoadedAt: Date?
    private var userPlaylistsNextCursorByUsername: [String: String?] = [:]
    private var userPlaylistsLoadedAtByUsername: [String: Date] = [:]
    private var detailLoadedAtById: [String: Date] = [:]
    private var loadPlaylistTasks: [String: Task<Void, Never>] = [:]
    private var loadPlaylistGenerations: [String: Int] = [:]

    func loadMyPlaylists(force: Bool = false) async {
        if isLoadingMyPlaylists { return }
        if !force,
           let myPlaylistsLoadedAt,
           Date().timeIntervalSince(myPlaylistsLoadedAt) < ttl,
           !myPlaylists.isEmpty {
            return
        }

        isLoadingMyPlaylists = true
        myPlaylistsError = nil

        do {
            let response: MyPlaylistsResponse = try await api.request(
                Endpoints.myPlaylists,
                method: .get,
                query: ["limit": String(pageSize)]
            )
            myPlaylists = response.playlists
            myPlaylistsNextCursor = response.pagination.nextCursor
            myPlaylistsHasMore = response.pagination.hasMore
            myPlaylistsLoadedAt = Date()
        } catch {
            myPlaylistsError = error.localizedDescription
        }

        isLoadingMyPlaylists = false
    }

    func loadMoreMyPlaylists() async {
        guard myPlaylistsHasMore, let cursor = myPlaylistsNextCursor, !isLoadingMoreMyPlaylists else {
            return
        }

        isLoadingMoreMyPlaylists = true

        do {
            let response: MyPlaylistsResponse = try await api.request(
                Endpoints.myPlaylists,
                method: .get,
                query: [
                    "limit": String(pageSize),
                    "cursor": cursor,
                ]
            )
            myPlaylists.append(contentsOf: response.playlists)
            myPlaylistsNextCursor = response.pagination.nextCursor
            myPlaylistsHasMore = response.pagination.hasMore
        } catch {
            myPlaylistsError = error.localizedDescription
        }

        isLoadingMoreMyPlaylists = false
    }

    func playlists(for username: String) -> [PlaylistSummary] {
        userPlaylistsByUsername[normalizeUsername(username)] ?? []
    }

    func loadUserPlaylists(username: String, force: Bool = false) async {
        let key = normalizeUsername(username)
        if isLoadingUserPlaylistsByUsername.contains(key) { return }

        if !force,
           let loadedAt = userPlaylistsLoadedAtByUsername[key],
           Date().timeIntervalSince(loadedAt) < ttl,
           userPlaylistsByUsername[key] != nil {
            return
        }

        isLoadingUserPlaylistsByUsername.insert(key)
        userPlaylistsErrorByUsername[key] = nil

        do {
            let response: MyPlaylistsResponse = try await api.request(
                Endpoints.userPlaylists(username: username),
                method: .get,
                query: ["limit": String(pageSize)]
            )
            userPlaylistsByUsername[key] = response.playlists
            userPlaylistsNextCursorByUsername[key] = response.pagination.nextCursor
            userPlaylistsHasMoreByUsername[key] = response.pagination.hasMore
            userPlaylistsLoadedAtByUsername[key] = Date()
        } catch {
            userPlaylistsErrorByUsername[key] = error.localizedDescription
        }

        isLoadingUserPlaylistsByUsername.remove(key)
    }

    func loadMoreUserPlaylists(username: String) async {
        let key = normalizeUsername(username)
        guard userPlaylistsHasMoreByUsername[key] == true,
              let cursor = userPlaylistsNextCursorByUsername[key],
              !isLoadingMoreUserPlaylistsByUsername.contains(key) else {
            return
        }

        isLoadingMoreUserPlaylistsByUsername.insert(key)

        do {
            let response: MyPlaylistsResponse = try await api.request(
                Endpoints.userPlaylists(username: username),
                method: .get,
                query: [
                    "limit": String(pageSize),
                    "cursor": cursor,
                ]
            )
            var merged = userPlaylistsByUsername[key] ?? []
            merged.append(contentsOf: response.playlists)
            userPlaylistsByUsername[key] = merged
            userPlaylistsNextCursorByUsername[key] = response.pagination.nextCursor
            userPlaylistsHasMoreByUsername[key] = response.pagination.hasMore
        } catch {
            userPlaylistsErrorByUsername[key] = error.localizedDescription
        }

        isLoadingMoreUserPlaylistsByUsername.remove(key)
    }

    func loadTrackMembership(trackId: String, force: Bool = false) async {
        if loadingTrackMembershipIds.contains(trackId) { return }
        if !force, trackMembershipsByTrackId[trackId] != nil { return }

        loadingTrackMembershipIds.insert(trackId)

        do {
            let response: PlaylistTrackMembershipResponse = try await api.request(
                Endpoints.myPlaylistTrackMembership,
                method: .get,
                query: ["nicheTrackId": trackId]
            )
            trackMembershipsByTrackId[trackId] = response.memberships
        } catch {
            if trackMembershipsByTrackId[trackId] == nil {
                trackMembershipsByTrackId[trackId] = []
            }
        }

        loadingTrackMembershipIds.remove(trackId)
    }

    func searchNicheTracks(query: String, limit: Int = 20) async throws -> [NicheTrackSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let response: NicheTrackSearchResponse = try await api.request(
            Endpoints.nicheTrackSearch,
            method: .get,
            query: [
                "q": trimmed,
                "limit": String(limit),
            ]
        )
        return response.tracks
    }

    func membership(for trackId: String, playlistId: String) -> PlaylistTrackMembership? {
        trackMembershipsByTrackId[trackId]?.first { $0.playlistId == playlistId }
    }

    func isTrackInPlaylist(trackId: String, playlistId: String) -> Bool {
        membership(for: trackId, playlistId: playlistId) != nil
    }

    func loadPlaylist(id: String, force: Bool = false) async {
        if !force,
           detailsById[id] != nil,
           let loadedAt = detailLoadedAtById[id],
           Date().timeIntervalSince(loadedAt) < ttl {
            return
        }

        if force {
            loadPlaylistTasks[id]?.cancel()
        } else if let existingTask = loadPlaylistTasks[id] {
            await existingTask.value
            return
        }

        let generation = (loadPlaylistGenerations[id] ?? 0) + 1
        loadPlaylistGenerations[id] = generation

        let task = Task { @MainActor in
            loadingDetailIds.insert(id)
            detailErrorsById[id] = nil

            defer {
                if loadPlaylistGenerations[id] == generation {
                    loadingDetailIds.remove(id)
                }
            }

            do {
                let response: PlaylistDetailResponse = try await api.request(
                    Endpoints.playlist(id: id),
                    method: .get,
                    query: ["limit": String(pageSize)]
                )
                try Task.checkCancellation()
                guard loadPlaylistGenerations[id] == generation else { return }
                detailsById[id] = response.playlist
                detailLoadedAtById[id] = Date()
            } catch is CancellationError {
                return
            } catch {
                if Self.isCancelled(error) { return }
                guard loadPlaylistGenerations[id] == generation else { return }
                if detailsById[id] == nil {
                    detailErrorsById[id] = error.localizedDescription
                }
            }
        }

        loadPlaylistTasks[id] = task
        await task.value
    }

    private static func isCancelled(_ error: Error) -> Bool {
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        if case APIClientError.network(let underlying) = error,
           let urlError = underlying as? URLError,
           urlError.code == .cancelled {
            return true
        }
        return false
    }

    func loadMorePlaylistItems(id: String) async {
        guard
            let detail = detailsById[id],
            detail.pagination.hasMore,
            let cursor = detail.pagination.nextCursor,
            !loadingMoreDetailIds.contains(id)
        else {
            return
        }

        loadingMoreDetailIds.insert(id)

        do {
            let response: PlaylistDetailResponse = try await api.request(
                Endpoints.playlist(id: id),
                method: .get,
                query: [
                    "limit": String(pageSize),
                    "cursor": cursor,
                ]
            )

            let merged = detail.withItems(
                detail.items + response.playlist.items,
                pagination: response.playlist.pagination
            )
            detailsById[id] = merged
        } catch {
            detailErrorsById[id] = error.localizedDescription
        }

        loadingMoreDetailIds.remove(id)
    }

    func loadAllPlaylistItems(id: String) async {
        await loadPlaylist(id: id, force: true)

        while detailsById[id]?.pagination.hasMore == true {
            await loadMorePlaylistItems(id: id)
        }
    }

    func moveItem(
        playlistId: String,
        itemId: String,
        afterSortKey: Double?,
        beforeSortKey: Double?,
        orderedItemIds: [String]
    ) async throws {
        let response: MovePlaylistItemResponse = try await api.request(
            Endpoints.movePlaylistItem(playlistId: playlistId, itemId: itemId),
            method: .post,
            body: MovePlaylistItemBody(
                afterSortKey: afterSortKey,
                beforeSortKey: beforeSortKey
            )
        )

        guard var detail = detailsById[playlistId] else { return }

        var itemsById = Dictionary(uniqueKeysWithValues: detail.items.map { ($0.id, $0) })
        if let moved = itemsById[itemId] {
            itemsById[itemId] = moved.withSortKey(response.item.sortKey)
        }

        let reordered = orderedItemIds.compactMap { itemsById[$0] }
        detail = detail.withItems(reordered)
        detailsById[playlistId] = detail
    }

    func createPlaylist(
        name: String,
        description: String?,
        visibility: PlaylistVisibility,
        coverJPEGData: Data? = nil
    ) async throws -> PlaylistSummary {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw PlaylistStoreError.invalidName
        }

        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        let response: CreatePlaylistResponse = try await api.request(
            Endpoints.createPlaylist,
            method: .post,
            body: CreatePlaylistBody(
                name: trimmedName,
                description: trimmedDescription,
                visibility: visibility,
                hasImage: coverJPEGData != nil,
                format: "jpeg"
            )
        )

        let playlistId = response.playlist?.id ?? response.playlistId
        guard let playlistId else {
            throw PlaylistStoreError.createFailed
        }

        var created: PlaylistSummary
        if let playlist = response.playlist {
            created = playlist
        } else {
            created = PlaylistSummary(
                id: playlistId,
                ownerId: "",
                name: trimmedName,
                description: trimmedDescription,
                visibility: visibility,
                imageUrl: nil,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                updatedAt: nil,
                trackCount: 0,
                saveCount: nil,
                shareCount: nil
            )
        }

        if let coverJPEGData, let upload = response.upload {
            created = try await uploadCoverImage(
                jpegData: coverJPEGData,
                playlistId: playlistId,
                upload: upload
            )
        }

        myPlaylists.insert(created, at: 0)
        myPlaylistsLoadedAt = Date()
        return created
    }

    func updatePlaylist(
        id: String,
        name: String,
        description: String?,
        visibility: PlaylistVisibility,
        coverJPEGData: Data?
    ) async throws -> PlaylistSummary {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw PlaylistStoreError.invalidName
        }

        let response: UpdatePlaylistResponse = try await api.request(
            Endpoints.updatePlaylist(id: id),
            method: .post,
            body: UpdatePlaylistBody(
                name: trimmedName,
                description: description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                visibility: visibility,
                hasImage: coverJPEGData != nil,
                format: "jpeg"
            )
        )

        var updated = response.playlist

        if let coverJPEGData, let upload = response.upload {
            updated = try await uploadCoverImage(
                jpegData: coverJPEGData,
                playlistId: id,
                upload: upload
            )
        }

        applySummary(updated)
        detailLoadedAtById[id] = nil
        await loadPlaylist(id: id, force: true)
        return updated
    }

    func deletePlaylist(id: String) async throws {
        let _: PlaylistSuccessResponse = try await api.request(
            Endpoints.deletePlaylist(id: id),
            method: .post
        )

        myPlaylists.removeAll { $0.id == id }
        detailsById[id] = nil
        detailLoadedAtById[id] = nil
        detailErrorsById[id] = nil
        myPlaylistsLoadedAt = Date()
    }

    private func applySummary(_ summary: PlaylistSummary) {
        if let index = myPlaylists.firstIndex(where: { $0.id == summary.id }) {
            myPlaylists[index] = summary
        }

        if let detail = detailsById[summary.id] {
            detailsById[summary.id] = detail.applying(summary)
        }
    }

    private func uploadCoverImage(
        jpegData: Data,
        playlistId: String,
        upload: PlaylistImageUploadInfo
    ) async throws -> PlaylistSummary {
        guard jpegData.count <= upload.maxBytes else {
            throw PlaylistStoreError.coverTooLarge
        }

        guard let uploadURL = URL(string: upload.uploadUrl) else {
            throw PlaylistStoreError.invalidUploadURL
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue(upload.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = jpegData

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw PlaylistStoreError.uploadFailed
        }

        let imageResponse: PlaylistImageUpdateResponse = try await api.request(
            Endpoints.updatePlaylistImage(playlistId: playlistId),
            method: .post,
            body: PlaylistImageUpdateBody(imageUrl: upload.publicUrl)
        )

        guard let playlist = imageResponse.playlist else {
            throw PlaylistStoreError.updateFailed
        }

        return playlist
    }

    func addTrack(playlistId: String, trackId: String) async throws {
        let response: PlaylistAddItemResponse = try await api.request(
            Endpoints.addPlaylistItem(playlistId: playlistId),
            method: .post,
            body: AddPlaylistItemBody(nicheTrackId: trackId),
            preserveBodyKeyNames: true
        )

        upsertMembership(
            trackId: trackId,
            playlistId: playlistId,
            itemId: response.item.id
        )

        if var detail = detailsById[playlistId],
           response.item.track != nil,
           !detail.items.contains(where: { $0.id == response.item.id }) {
            detail = detail.withItems(detail.items + [response.item])
            detailsById[playlistId] = detail
        } else {
            await loadPlaylist(id: playlistId, force: true)
        }
    }

    func removeTrack(playlistId: String, trackId: String, itemId: String) async throws {
        try await removeItem(playlistId: playlistId, itemId: itemId)
        removeMembership(trackId: trackId, playlistId: playlistId)
    }

    func removeItem(playlistId: String, itemId: String) async throws {
        let _: PlaylistSuccessResponse = try await api.request(
            Endpoints.deletePlaylistItem(playlistId: playlistId, itemId: itemId),
            method: .post
        )

        guard var detail = detailsById[playlistId] else { return }
        detail = detail.withItems(detail.items.filter { $0.id != itemId })
        detailsById[playlistId] = detail
    }

    private func upsertMembership(trackId: String, playlistId: String, itemId: String) {
        var memberships = trackMembershipsByTrackId[trackId] ?? []
        memberships.removeAll { $0.playlistId == playlistId }
        memberships.append(
            PlaylistTrackMembership(
                playlistId: playlistId,
                itemId: itemId,
                nicheTrackId: trackId,
                createdAt: ISO8601DateFormatter().string(from: Date())
            )
        )
        trackMembershipsByTrackId[trackId] = memberships
    }

    private func removeMembership(trackId: String, playlistId: String) {
        guard var memberships = trackMembershipsByTrackId[trackId] else { return }
        memberships.removeAll { $0.playlistId == playlistId }
        trackMembershipsByTrackId[trackId] = memberships
    }

    func reset() {
        myPlaylists = []
        myPlaylistsNextCursor = nil
        myPlaylistsHasMore = false
        myPlaylistsLoadedAt = nil
        myPlaylistsError = nil
        detailsById = [:]
        detailLoadedAtById = [:]
        detailErrorsById = [:]
        trackMembershipsByTrackId = [:]
        loadingTrackMembershipIds = []
        userPlaylistsByUsername = [:]
        userPlaylistsNextCursorByUsername = [:]
        userPlaylistsLoadedAtByUsername = [:]
        userPlaylistsErrorByUsername = [:]
        userPlaylistsHasMoreByUsername = [:]
        isLoadingUserPlaylistsByUsername = []
        isLoadingMoreUserPlaylistsByUsername = []
    }
}

private extension PlaylistStore {
    func normalizeUsername(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum PlaylistStoreError: LocalizedError {
    case invalidName
    case createFailed
    case updateFailed
    case coverTooLarge
    case invalidUploadURL
    case uploadFailed

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Playlist name is required."
        case .createFailed:
            return "Could not create playlist."
        case .updateFailed:
            return "Could not update playlist."
        case .coverTooLarge:
            return "Cover image is too large."
        case .invalidUploadURL:
            return "Could not prepare cover upload."
        case .uploadFailed:
            return "Could not upload cover image."
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
