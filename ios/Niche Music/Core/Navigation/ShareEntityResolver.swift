//
//  ShareEntityResolver.swift
//  Niche Music
//

import Foundation

struct ShareEntityMeta: Decodable {
    let source: String?
    let sourceId: String?
}

private struct ShareEntityEnvelope: Decodable {
    let success: Bool
    let result: ShareEntityMeta?
}

enum ShareEntityResolver {
    private static let api = APIClient.shared

    static func resolveTrackDestination(trackId: String) async -> DeepLinkDestination {
        if let meta = await fetchEntity(kind: .track, id: trackId) {
            if meta.source == "apple_music", let sourceId = meta.sourceId, !sourceId.isEmpty {
                return .track(TrackDetailReference(id: nil, source: "apple_music", sourceId: sourceId))
            }
        }
        return .track(TrackDetailReference(id: trackId, source: "niche", sourceId: nil))
    }

    static func resolveArtistDestination(artistId: String) async -> DeepLinkDestination? {
        if let meta = await fetchEntity(kind: .artist, id: artistId),
           meta.source == "apple_music",
           let sourceId = meta.sourceId,
           !sourceId.isEmpty {
            return .appleArtist(sourceId: sourceId)
        }
        return nil
    }

    private enum EntityKind {
        case track
        case artist
    }

    private static func fetchEntity(kind: EntityKind, id: String) async -> ShareEntityMeta? {
        let endpoint: APIEndpoint
        switch kind {
        case .track:
            endpoint = Endpoints.publicShareTrack(id: id)
        case .artist:
            endpoint = Endpoints.publicShareArtist(id: id)
        }

        do {
            let response: ShareEntityEnvelope = try await api.request(endpoint, method: .get)
            guard response.success else { return nil }
            return response.result
        } catch {
            return nil
        }
    }
}
