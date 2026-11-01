//
//  MusicDetailModels.swift
//  Niche Music
//

import Foundation

struct TrackSocialViewer: Decodable, Equatable {
    var isLiked: Bool
    var isSaved: Bool
}

struct AlbumSocialViewer: Decodable, Equatable {
    var isLiked: Bool
    var isSaved: Bool
}

struct ArtistSocialViewer: Decodable, Equatable {
    var isFan: Bool
    var isOwner: Bool
}

struct CatalogTrack: Decodable, Equatable, Identifiable {
    let id: String
    let source: String
    let sourceId: String
    let name: String
    let artworkUrl: String?
    let artistId: String?
    let albumId: String?
    let previewUrl: String?
    let releaseDate: String?
    let likeCount: Int
    let saveCount: Int
    let shareCount: Int
    let viewer: TrackSocialViewer?
    var artistName: String?
}

struct CatalogAlbum: Decodable, Equatable, Identifiable {
    let id: String
    let source: String
    let sourceId: String
    let name: String
    let artistId: String?
    let artworkUrl: String?
    let copyright: String?
    let editorialNote: String?
    let releaseDate: String?
    let trackCount: Int?
    let likeCount: Int
    let saveCount: Int
    let shareCount: Int
    let viewer: AlbumSocialViewer?
}

struct CatalogArtist: Decodable, Equatable, Identifiable {
    let id: String
    let source: String
    let sourceId: String
    let name: String
    let imageUrl: String?
    let ownerId: String?
    let fanCount: Int?
    let shareCount: Int
    let hasFullDiscography: Bool?
}

struct AppleSongDetailResponse: Decodable {
    let track: CatalogTrack
    let artist: CatalogArtist?
    let album: CatalogAlbum?
    let viewer: TrackSocialViewer
}

struct AppleAlbumDetailResponse: Decodable {
    let album: CatalogAlbum
    let artist: CatalogArtist?
    let viewer: AlbumSocialViewer
    let songs: [CatalogTrack]
}

struct AppleArtistDetailResponse: Decodable {
    let artist: CatalogArtist
    let viewer: ArtistSocialViewer
    let albums: [CatalogAlbum]
    let songs: [CatalogTrack]
}

struct NicheAlbumSummary: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let artworkUrl: String
    let ownerId: String
    let releaseDate: String
    let releaseType: String?
    let trackCount: Int
    let likeCount: Int
    let saveCount: Int
    let shareCount: Int

    init(
        id: String,
        name: String,
        artworkUrl: String,
        ownerId: String,
        releaseDate: String,
        releaseType: String? = nil,
        trackCount: Int,
        likeCount: Int,
        saveCount: Int,
        shareCount: Int
    ) {
        self.id = id
        self.name = name
        self.artworkUrl = artworkUrl
        self.ownerId = ownerId
        self.releaseDate = releaseDate
        self.releaseType = releaseType
        self.trackCount = trackCount
        self.likeCount = likeCount
        self.saveCount = saveCount
        self.shareCount = shareCount
    }
}

struct NicheAlbumTrackRow: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let artworkUrl: String
    let musicUrl: String
    let releaseDate: String
    let durationMs: Int
    let explicit: Bool
    let likeCount: Int
    let trackNumber: Int?
    let credits: [NicheTrackCredit]?
    let viewer: TrackSocialViewer?

    init(
        id: String,
        name: String,
        artworkUrl: String,
        musicUrl: String,
        releaseDate: String,
        durationMs: Int,
        explicit: Bool,
        likeCount: Int,
        trackNumber: Int?,
        credits: [NicheTrackCredit]?,
        viewer: TrackSocialViewer?
    ) {
        self.id = id
        self.name = name
        self.artworkUrl = artworkUrl
        self.musicUrl = musicUrl
        self.releaseDate = releaseDate
        self.durationMs = durationMs
        self.explicit = explicit
        self.likeCount = likeCount
        self.trackNumber = trackNumber
        self.credits = credits
        self.viewer = viewer
    }

    func primaryArtistName(fallbackOwner: FullUser) -> String {
        if let primary = credits?.first(where: { $0.isPrimary == true })?.artist {
            return primary.displayName ?? primary.username
        }
        if let artist = credits?.first?.artist {
            return artist.displayName ?? artist.username
        }
        return fallbackOwner.displayName ?? fallbackOwner.username
    }

    func asNicheTrack(owner: FullUser) -> NicheTrack? {
        guard !musicUrl.isEmpty, let url = URL(string: musicUrl) else { return nil }
        guard !artworkUrl.isEmpty, URL(string: artworkUrl) != nil else { return nil }
        _ = url

        return NicheTrack(
            id: id,
            ownerId: owner.id,
            name: name,
            artworkUrl: artworkUrl,
            musicUrl: musicUrl,
            releaseDate: releaseDate,
            explicit: explicit,
            featuredDurations: nil,
            hasLyrics: false,
            durationMs: durationMs,
            popularity: 0,
            bpm: 0,
            gain: 0,
            createdAt: releaseDate,
            updatedAt: nil,
            deletedAt: nil,
            visibility: .public,
            likeCount: likeCount,
            saveCount: 0,
            shareCount: 0,
            owner: owner,
            momentUrl: nil,
            credits: credits,
            metadata: nil
        )
    }
}

private struct NicheAlbumTrackRowPayload: Decodable {
    let id: String
    let name: String
    let artworkUrl: String?
    let musicUrl: String?
    let releaseDate: String?
    let durationMs: Int
    let explicit: Bool
    let likeCount: Int
    let trackNumber: Int?
    let credits: [NicheTrackCredit]?
    let viewer: TrackSocialViewer?

    func resolved(album: NicheAlbumSummary) -> NicheAlbumTrackRow {
        NicheAlbumTrackRow(
            id: id,
            name: name,
            artworkUrl: resolvedURL(artworkUrl, fallback: album.artworkUrl),
            musicUrl: musicUrl ?? "",
            releaseDate: releaseDate ?? album.releaseDate,
            durationMs: durationMs,
            explicit: explicit,
            likeCount: likeCount,
            trackNumber: trackNumber,
            credits: credits,
            viewer: viewer
        )
    }

    private func resolvedURL(_ value: String?, fallback: String) -> String {
        if let value, !value.isEmpty {
            return value
        }
        return fallback
    }
}

struct NicheAlbumDetailResponse: Decodable {
    let album: NicheAlbumSummary
    let owner: FullUser
    let viewer: AlbumSocialViewer
    let tracks: [NicheAlbumTrackRow]

    enum CodingKeys: String, CodingKey {
        case album
        case owner
        case viewer
        case tracks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedAlbum = try container.decode(NicheAlbumSummary.self, forKey: .album)
        album = decodedAlbum
        owner = try container.decode(FullUser.self, forKey: .owner)
        viewer = try container.decode(AlbumSocialViewer.self, forKey: .viewer)
        let rawTracks = try container.decode([NicheAlbumTrackRowPayload].self, forKey: .tracks)
        tracks = rawTracks.map { $0.resolved(album: decodedAlbum) }
    }

    init(
        album: NicheAlbumSummary,
        owner: FullUser,
        viewer: AlbumSocialViewer,
        tracks: [NicheAlbumTrackRow]
    ) {
        self.album = album
        self.owner = owner
        self.viewer = viewer
        self.tracks = tracks
    }
}

struct AppleAlbumSyncResponse: Decodable {
    let syncSucceeded: Bool
}

struct AppleDiscographySyncResponse: Decodable {
    let syncSucceeded: Bool
}

struct MusicShareResponse: Decodable {
    let message: String?
}

enum MusicShareLinks {
    static let host = "https://share.nichemusic.app"

    static func track(_ id: String) -> URL {
        URL(string: "\(host)/track/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)")!
    }

    static func album(_ id: String) -> URL {
        URL(string: "\(host)/album/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)")!
    }

    static func artist(_ id: String) -> URL {
        URL(string: "\(host)/artist/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)")!
    }

    static func playlist(_ id: String) -> URL {
        URL(string: "\(host)/playlist/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)")!
    }
}
