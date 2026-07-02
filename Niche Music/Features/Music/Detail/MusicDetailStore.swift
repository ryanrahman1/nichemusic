//
//  MusicDetailStore.swift
//  Niche Music
//

import Foundation

@MainActor
final class MusicDetailStore {
    static let shared = MusicDetailStore()

    private let ttl: TimeInterval = 600
    private var songLoadedAt: [String: Date] = [:]
    private var albumLoadedAt: [String: Date] = [:]
    private var artistLoadedAt: [String: Date] = [:]
    private var nicheAlbumLoadedAt: [String: Date] = [:]

    private var inFlightSongs: [String: Task<AppleSongDetailResponse, Error>] = [:]
    private var inFlightAlbums: [String: Task<AppleAlbumDetailResponse, Error>] = [:]
    private var inFlightArtists: [String: Task<AppleArtistDetailResponse, Error>] = [:]
    private var inFlightNicheAlbums: [String: Task<NicheAlbumDetailResponse, Error>] = [:]

    private var songCache: [String: AppleSongDetailResponse] = [:]
    private var albumCache: [String: AppleAlbumDetailResponse] = [:]
    private var artistCache: [String: AppleArtistDetailResponse] = [:]
    private var nicheAlbumCache: [String: NicheAlbumDetailResponse] = [:]

    private init() {}

    func cachedSong(sourceId: String) -> AppleSongDetailResponse? {
        guard let loadedAt = songLoadedAt[sourceId],
              Date().timeIntervalSince(loadedAt) < ttl else { return nil }
        return songCache[sourceId]
    }

    func loadAppleSong(sourceId: String, force: Bool = false) async throws -> AppleSongDetailResponse {
        if !force, let cached = cachedSong(sourceId: sourceId) {
            return cached
        }

        if let task = inFlightSongs[sourceId] {
            return try await task.value
        }

        let task = Task<AppleSongDetailResponse, Error> {
            let response: AppleSongDetailResponse = try await APIClient.shared.request(
                Endpoints.appleMusicSong(id: sourceId),
                method: .get
            )
            return response
        }

        inFlightSongs[sourceId] = task

        do {
            let response = try await task.value
            songCache[sourceId] = response
            songLoadedAt[sourceId] = Date()
            inFlightSongs[sourceId] = nil
            return response
        } catch {
            inFlightSongs[sourceId] = nil
            throw error
        }
    }

    func loadAppleAlbum(sourceId: String, force: Bool = false) async throws -> AppleAlbumDetailResponse {
        if !force,
           let loadedAt = albumLoadedAt[sourceId],
           Date().timeIntervalSince(loadedAt) < ttl,
           let cached = albumCache[sourceId] {
            return cached
        }

        if let task = inFlightAlbums[sourceId] {
            return try await task.value
        }

        let task = Task<AppleAlbumDetailResponse, Error> {
            try await APIClient.shared.request(
                Endpoints.appleMusicAlbum(id: sourceId),
                method: .get
            )
        }

        inFlightAlbums[sourceId] = task

        do {
            let response = try await task.value
            albumCache[sourceId] = response
            albumLoadedAt[sourceId] = Date()
            inFlightAlbums[sourceId] = nil
            return response
        } catch {
            inFlightAlbums[sourceId] = nil
            throw error
        }
    }

    func loadAppleArtist(sourceId: String, force: Bool = false) async throws -> AppleArtistDetailResponse {
        if !force,
           let loadedAt = artistLoadedAt[sourceId],
           Date().timeIntervalSince(loadedAt) < ttl,
           let cached = artistCache[sourceId] {
            return cached
        }

        if let task = inFlightArtists[sourceId] {
            return try await task.value
        }

        let task = Task<AppleArtistDetailResponse, Error> {
            try await APIClient.shared.request(
                Endpoints.appleMusicArtist(id: sourceId),
                method: .get
            )
        }

        inFlightArtists[sourceId] = task

        do {
            let response = try await task.value
            artistCache[sourceId] = response
            artistLoadedAt[sourceId] = Date()
            inFlightArtists[sourceId] = nil
            return response
        } catch {
            inFlightArtists[sourceId] = nil
            throw error
        }
    }

    func loadNicheAlbum(id: String, force: Bool = false) async throws -> NicheAlbumDetailResponse {
        if !force,
           let loadedAt = nicheAlbumLoadedAt[id],
           Date().timeIntervalSince(loadedAt) < ttl,
           let cached = nicheAlbumCache[id] {
            return cached
        }

        if let task = inFlightNicheAlbums[id] {
            return try await task.value
        }

        let task = Task<NicheAlbumDetailResponse, Error> {
            try await APIClient.shared.request(
                Endpoints.nicheAlbum(id: id),
                method: .get
            )
        }

        inFlightNicheAlbums[id] = task

        do {
            let response = try await task.value
            nicheAlbumCache[id] = response
            nicheAlbumLoadedAt[id] = Date()
            inFlightNicheAlbums[id] = nil
            return response
        } catch {
            inFlightNicheAlbums[id] = nil
            throw error
        }
    }

    func syncAppleAlbum(sourceId: String) async throws -> Bool {
        let response: AppleAlbumSyncResponse = try await APIClient.shared.request(
            Endpoints.appleMusicAlbumSync(id: sourceId),
            method: .post
        )
        albumLoadedAt.removeValue(forKey: sourceId)
        albumCache.removeValue(forKey: sourceId)
        return response.syncSucceeded
    }

    func loadAppleArtistDiscography(sourceId: String) async throws -> Bool {
        let response: AppleDiscographySyncResponse = try await APIClient.shared.request(
            Endpoints.appleMusicArtistDiscography(id: sourceId),
            method: .post
        )
        artistLoadedAt.removeValue(forKey: sourceId)
        artistCache.removeValue(forKey: sourceId)
        return response.syncSucceeded
    }

    func setTrackLike(trackId: String, liked: Bool) async throws {
        let endpoint = liked ? Endpoints.likeSong(id: trackId) : Endpoints.unlikeSong(id: trackId)
        let _: MusicShareResponse = try await APIClient.shared.request(endpoint, method: .post)
    }

    func setNicheTrackLike(trackId: String, liked: Bool) async throws {
        let endpoint = liked ? Endpoints.likeNicheSong(id: trackId) : Endpoints.unlikeNicheSong(id: trackId)
        let _: MusicShareResponse = try await APIClient.shared.request(endpoint, method: .post)
    }

    func setTrackSave(trackId: String, saved: Bool) async throws {
        let endpoint = saved ? Endpoints.saveSong(id: trackId) : Endpoints.unsaveSong(id: trackId)
        let _: MusicShareResponse = try await APIClient.shared.request(endpoint, method: .post)
    }

    func setNicheTrackSave(trackId: String, saved: Bool) async throws {
        let endpoint = saved ? Endpoints.saveNicheSong(id: trackId) : Endpoints.unsaveNicheSong(id: trackId)
        let _: MusicShareResponse = try await APIClient.shared.request(endpoint, method: .post)
    }

    func recordTrackShare(trackId: String) async throws {
        let _: MusicShareResponse = try await APIClient.shared.request(
            Endpoints.shareSong(id: trackId),
            method: .post
        )
    }

    func setAlbumLike(albumId: String, liked: Bool) async throws {
        let endpoint = liked ? Endpoints.likeAlbum(id: albumId) : Endpoints.unlikeAlbum(id: albumId)
        let _: MusicShareResponse = try await APIClient.shared.request(endpoint, method: .post)
    }

    func setAlbumSave(albumId: String, saved: Bool) async throws {
        let endpoint = saved ? Endpoints.saveAlbum(id: albumId) : Endpoints.unsaveAlbum(id: albumId)
        let _: MusicShareResponse = try await APIClient.shared.request(endpoint, method: .post)
    }

    func recordAlbumShare(albumId: String) async throws {
        let _: MusicShareResponse = try await APIClient.shared.request(
            Endpoints.shareAlbum(id: albumId),
            method: .post
        )
    }

    func setArtistFan(artistId: String, isFan: Bool) async throws {
        let endpoint = isFan ? Endpoints.followArtist(id: artistId) : Endpoints.unfollowArtist(id: artistId)
        let _: MusicShareResponse = try await APIClient.shared.request(endpoint, method: .post)
    }

    func recordArtistShare(artistId: String) async throws {
        let _: MusicShareResponse = try await APIClient.shared.request(
            Endpoints.shareArtist(id: artistId),
            method: .post
        )
    }
}
