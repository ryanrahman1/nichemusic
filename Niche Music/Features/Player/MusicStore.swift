//
//  MusicStore.swift
//  Niche Music
//
//  Created by Ryan Rahman on 5/25/26.
//


import Foundation
import Combine

enum LyricsCacheEntry {
    case found(TrackLyrics)
    case notFound
}

struct NicheTrackDetailPayload {
    let track: NicheTrack
    let viewer: TrackViewer
}

@MainActor
final class MusicStore: ObservableObject {
    @Published private(set) var tracksById: [String: NicheTrack] = [:]
    @Published private(set) var viewerByTrackId: [String: TrackViewer] = [:]
    @Published var isLoadingTrack = false
    @Published var errorMessage: String?

    @Published private(set) var likeBusyTrackIds: Set<String> = []

    private var trackLoadedAtById: [String: Date] = [:]
    private var inFlightTrackTasks: [String: Task<(NicheTrack, TrackViewer), Error>] = [:]
    private var inFlightDetailTasks: [String: Task<NicheTrackDetailPayload, Error>] = [:]

    private let trackTtl: TimeInterval = 600 // 10 minutes
    
    @Published private(set) var lyricsByTrackId: [String: TrackLyrics] = [:]

    private var lyricsCacheByTrackId: [String: LyricsCacheEntry] = [:]
    private var lyricsLoadedAtByTrackId: [String: Date] = [:]
    private var inFlightLyricsTasks: [String: Task<LyricsCacheEntry, Error>] = [:]

    private let lyricsTtl: TimeInterval = 600
    private let missingLyricsTtl: TimeInterval = 1800 // 30 min

    func track(id: String) -> NicheTrack? {
        tracksById[id]
    }

    func viewer(for trackId: String) -> TrackViewer {
        viewerByTrackId[trackId] ?? TrackViewer(isLiked: false, isSaved: false)
    }

    func hasViewerContext(for trackId: String) -> Bool {
        viewerByTrackId[trackId] != nil
    }

    func isLikeBusy(trackId: String) -> Bool {
        likeBusyTrackIds.contains(trackId)
    }

    func toggleTrackLike(trackId: String) async {
        guard !likeBusyTrackIds.contains(trackId) else { return }

        if tracksById[trackId] == nil {
            guard (try? await fetchTrackDetail(id: trackId)) != nil else { return }
        }

        guard let track = tracksById[trackId] else { return }

        likeBusyTrackIds.insert(trackId)
        defer { likeBusyTrackIds.remove(trackId) }

        let currentViewer = viewer(for: trackId)
        let next = !currentViewer.isLiked
        let previousViewer = currentViewer
        let previousTrack = track

        viewerByTrackId[trackId] = TrackViewer(isLiked: next, isSaved: currentViewer.isSaved)
        tracksById[trackId] = copyTrack(track, likeDelta: next ? 1 : -1, saveDelta: 0)

        do {
            try await MusicDetailStore.shared.setNicheTrackLike(trackId: trackId, liked: next)
        } catch {
            viewerByTrackId[trackId] = previousViewer
            tracksById[trackId] = previousTrack
            errorMessage = error.localizedDescription
        }
    }

    func loadTrack(id: String, force: Bool = false) async -> NicheTrack? {
        do {
            return try await fetchTrack(id: id, force: force)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func fetchTrack(id: String, force: Bool = false) async throws -> NicheTrack {
        if !force,
           let cached = tracksById[id],
           let loadedAt = trackLoadedAtById[id],
           Date().timeIntervalSince(loadedAt) < trackTtl {
            return cached
        }

        if let task = inFlightTrackTasks[id] {
            return try await task.value.0
        }

        isLoadingTrack = true
        errorMessage = nil

        let task = Task<(NicheTrack, TrackViewer), Error> {
            let response: NicheTrackResponse = try await APIClient.shared.request(
                Endpoints.custom(path: "/music/niche/songs/\(id)"),
                method: .get
            )

            return (
                response.track,
                response.viewer ?? TrackViewer(isLiked: false, isSaved: false)
            )
        }

        inFlightTrackTasks[id] = task

        do {
            let (track, viewer) = try await task.value

            tracksById[id] = track
            viewerByTrackId[id] = viewer
            trackLoadedAtById[id] = Date()
            inFlightTrackTasks[id] = nil
            isLoadingTrack = false

            return track
        } catch {
            inFlightTrackTasks[id] = nil
            isLoadingTrack = false
            throw error
        }
    }

    private func copyTrack(_ track: NicheTrack, likeDelta: Int, saveDelta: Int) -> NicheTrack {
        NicheTrack(
            id: track.id,
            ownerId: track.ownerId,
            name: track.name,
            artworkUrl: track.artworkUrl,
            musicUrl: track.musicUrl,
            releaseDate: track.releaseDate,
            explicit: track.explicit,
            featuredDurations: track.featuredDurations,
            hasLyrics: track.hasLyrics,
            durationMs: track.durationMs,
            popularity: track.popularity,
            bpm: track.bpm,
            gain: track.gain,
            createdAt: track.createdAt,
            updatedAt: track.updatedAt,
            deletedAt: track.deletedAt,
            visibility: track.visibility,
            likeCount: max(0, track.likeCount + likeDelta),
            saveCount: max(0, track.saveCount + saveDelta),
            shareCount: track.shareCount,
            owner: track.owner,
            momentUrl: track.momentUrl,
            credits: track.credits,
            metadata: track.metadata
        )
    }

    func fetchTrackDetail(id: String, force: Bool = false) async throws -> NicheTrackDetailPayload {
        if !force,
           let cached = tracksById[id],
           cached.credits != nil,
           let loadedAt = trackLoadedAtById[id],
           Date().timeIntervalSince(loadedAt) < trackTtl {
            return NicheTrackDetailPayload(
                track: cached,
                viewer: viewerByTrackId[id] ?? TrackViewer(isLiked: false, isSaved: false)
            )
        }

        if !force, let task = inFlightDetailTasks[id] {
            return try await task.value
        }

        isLoadingTrack = true
        errorMessage = nil

        let task = Task<NicheTrackDetailPayload, Error> {
            let response: NicheTrackResponse = try await APIClient.shared.request(
                Endpoints.custom(path: "/music/niche/songs/\(id)"),
                method: .get
            )

            return NicheTrackDetailPayload(
                track: response.track,
                viewer: response.viewer ?? TrackViewer(isLiked: false, isSaved: false)
            )
        }

        inFlightDetailTasks[id] = task

        do {
            let payload = try await task.value

            tracksById[id] = payload.track
            trackLoadedAtById[id] = Date()
            viewerByTrackId[id] = payload.viewer
            inFlightDetailTasks[id] = nil
            isLoadingTrack = false

            return payload
        } catch {
            inFlightDetailTasks[id] = nil
            isLoadingTrack = false
            throw error
        }
    }
    
    func lyrics(for trackId: String) -> TrackLyrics? {
        lyricsByTrackId[trackId]
    }

    func loadLyrics(trackId: String, force: Bool = false) async -> LyricsCacheEntry {
        do {
            return try await fetchLyrics(trackId: trackId, force: force)
        } catch {
            errorMessage = error.localizedDescription
            return .notFound
        }
    }

    func fetchLyrics(trackId: String, force: Bool = false) async throws -> LyricsCacheEntry {
        if !force,
           let cached = lyricsCacheByTrackId[trackId],
           let loadedAt = lyricsLoadedAtByTrackId[trackId] {
            let ttl = ttlForLyricsEntry(cached)

            if Date().timeIntervalSince(loadedAt) < ttl {
                return cached
            }
        }

        if let task = inFlightLyricsTasks[trackId] {
            return try await task.value
        }

        let task = Task<LyricsCacheEntry, Error> {
            do {
                let response: TrackLyricsResponse = try await APIClient.shared.request(
                    Endpoints.trackLyrics(id: trackId),
                    method: .get
                )

                return .found(response.lyrics)
            } catch {
                if Self.isLyricsNotFoundError(error) {
                    return .notFound
                }

                throw error
            }
        }

        inFlightLyricsTasks[trackId] = task

        do {
            let entry = try await task.value

            lyricsCacheByTrackId[trackId] = entry
            lyricsLoadedAtByTrackId[trackId] = Date()
            inFlightLyricsTasks[trackId] = nil

            if case .found(let lyrics) = entry {
                lyricsByTrackId[trackId] = lyrics
            } else {
                lyricsByTrackId.removeValue(forKey: trackId)
            }

            return entry
        } catch {
            inFlightLyricsTasks[trackId] = nil
            throw error
        }
    }

    private func ttlForLyricsEntry(_ entry: LyricsCacheEntry) -> TimeInterval {
        switch entry {
        case .found:
            return lyricsTtl
        case .notFound:
            return missingLyricsTtl
        }
    }
    
    private static func isLyricsNotFoundError(_ error: Error) -> Bool {
        let message = error.localizedDescription

        return message.contains("MUSIC_NICHE_SONG_LYRICS_NOT_FOUND")
            || message.contains("Lyrics not found")
            || message.contains("404")
    }

    func preloadTracks(ids: [String], force: Bool = false) async {
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { [weak self] in
                    guard let self else { return }
                    _ = await self.loadTrack(id: id, force: force)
                }
            }
        }
    }
    
    func clearCache() {
        tracksById.removeAll()
        viewerByTrackId.removeAll()
        trackLoadedAtById.removeAll()
        inFlightTrackTasks.removeAll()
        likeBusyTrackIds.removeAll()
        lyricsByTrackId.removeAll()
        lyricsLoadedAtByTrackId.removeAll()
        inFlightLyricsTasks.removeAll()
    }
}

#if DEBUG
extension MusicStore {
    static var preview: MusicStore {
        let store = MusicStore()
        // store.tracksById["track-id"] = NicheTrack.preview
        return store
    }
}
#endif
