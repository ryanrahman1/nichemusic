//
//  PlaylistModels.swift
//  Niche Music
//

import Foundation

enum PlaylistVisibility: String, Decodable, Encodable, CaseIterable, Identifiable {
    case `public`
    case `private`
    case unlisted

    var id: String { rawValue }

    var label: String {
        switch self {
        case .public: return "Public"
        case .private: return "Private"
        case .unlisted: return "Unlisted"
        }
    }

    var iconName: String {
        switch self {
        case .public: return "globe"
        case .private: return "lock.fill"
        case .unlisted: return "link"
        }
    }
}

struct PlaylistSummary: Decodable, Identifiable, Equatable {
    let id: String
    let ownerId: String
    let name: String
    let description: String?
    let visibility: PlaylistVisibility
    let imageUrl: String?
    let createdAt: String
    let updatedAt: String?
    let trackCount: Int?
    let saveCount: Int?
    let shareCount: Int?
}

struct PlaylistPagination: Decodable, Equatable {
    let limit: Int?
    let hasMore: Bool
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case limit
        case hasMore
        case nextCursor
    }
}

struct MyPlaylistsResponse: Decodable {
    let playlists: [PlaylistSummary]
    let pagination: PlaylistPagination
}

struct PlaylistTrackMembershipResponse: Decodable {
    let memberships: [PlaylistTrackMembership]
}

struct PlaylistTrackMembership: Decodable, Equatable, Identifiable {
    let playlistId: String
    let itemId: String
    let nicheTrackId: String
    let createdAt: String

    var id: String { "\(playlistId)-\(nicheTrackId)" }

    init(playlistId: String, itemId: String, nicheTrackId: String, createdAt: String) {
        self.playlistId = playlistId
        self.itemId = itemId
        self.nicheTrackId = nicheTrackId
        self.createdAt = createdAt
    }
}

struct CreatePlaylistResponse: Decodable {
    let playlist: PlaylistSummary?
    let playlistId: String?
    let upload: PlaylistImageUploadInfo?
}

struct PlaylistImageUploadInfo: Decodable {
    let uploadUrl: String
    let publicUrl: String
    let objectKey: String
    let contentType: String
    let maxBytes: Int
}

struct PlaylistDetailResponse: Decodable {
    let playlist: PlaylistDetail
}

struct PlaylistDetail: Decodable, Identifiable, Equatable {
    let id: String
    let ownerId: String
    let name: String
    let description: String?
    let visibility: PlaylistVisibility
    let imageUrl: String?
    let createdAt: String
    let updatedAt: String?
    let trackCount: Int?
    let saveCount: Int?
    let shareCount: Int?
    let owner: PlaylistProfileRef?
    let items: [PlaylistItem]
    let pagination: PlaylistPagination

    var displayTrackCount: Int {
        let loaded = items.count
        if let trackCount, trackCount > loaded {
            return trackCount
        }
        return loaded
    }
}

struct PlaylistItem: Decodable, Identifiable, Equatable {
    let id: String
    let playlistId: String
    let nicheTrackId: String
    let addedById: String?
    let sortKey: Double
    let createdAt: String
    let track: PlaylistItemTrack?

    enum CodingKeys: String, CodingKey {
        case id
        case playlistId
        case nicheTrackId
        case addedById
        case sortKey
        case createdAt
        case track
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        playlistId = try container.decode(String.self, forKey: .playlistId)
        nicheTrackId = try container.decode(String.self, forKey: .nicheTrackId)
        addedById = try container.decodeIfPresent(String.self, forKey: .addedById)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        track = try container.decodeIfPresent(PlaylistItemTrack.self, forKey: .track)

        if let intKey = try? container.decode(Int.self, forKey: .sortKey) {
            sortKey = Double(intKey)
        } else {
            sortKey = try container.decode(Double.self, forKey: .sortKey)
        }
    }

    init(
        id: String,
        playlistId: String,
        nicheTrackId: String,
        addedById: String?,
        sortKey: Double,
        createdAt: String,
        track: PlaylistItemTrack?
    ) {
        self.id = id
        self.playlistId = playlistId
        self.nicheTrackId = nicheTrackId
        self.addedById = addedById
        self.sortKey = sortKey
        self.createdAt = createdAt
        self.track = track
    }

    func withSortKey(_ sortKey: Double) -> PlaylistItem {
        PlaylistItem(
            id: id,
            playlistId: playlistId,
            nicheTrackId: nicheTrackId,
            addedById: addedById,
            sortKey: sortKey,
            createdAt: createdAt,
            track: track
        )
    }
}

struct PlaylistProfileRef: Decodable, Equatable {
    let id: String
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let isVerified: Bool?
    let verificationType: String?
}

struct PlaylistTrackArtistRef: Decodable, Equatable {
    let isPrimary: Bool?
    let artist: PlaylistProfileRef?
}

struct PlaylistTrackViewerContext: Decodable, Equatable {
    let isLiked: Bool
}

struct PlaylistItemTrack: Decodable, Equatable, Identifiable {
    let id: String
    let ownerId: String
    let name: String
    let artworkUrl: String?
    let musicUrl: String?
    let releaseDate: String?
    let explicit: Bool?
    let durationMs: Int?
    let popularity: Int?
    let bpm: Int?
    let gain: Int?
    let hasLyrics: Bool?
    let momentUrl: String?
    let visibility: String?
    let likeCount: Int?
    let saveCount: Int?
    let shareCount: Int?
    let createdAt: String?
    let updatedAt: String?
    let owner: PlaylistProfileRef?
    let artists: [PlaylistTrackArtistRef]?
    let viewerContext: PlaylistTrackViewerContext?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId
        case name
        case artworkUrl
        case musicUrl
        case releaseDate
        case explicit
        case durationMs
        case popularity
        case bpm
        case gain
        case hasLyrics
        case momentUrl
        case visibility
        case likeCount
        case saveCount
        case shareCount
        case createdAt
        case updatedAt
        case owner
        case artists
        case viewerContext
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        ownerId = try container.decode(String.self, forKey: .ownerId)
        name = try container.decode(String.self, forKey: .name)
        artworkUrl = try container.decodeIfPresent(String.self, forKey: .artworkUrl)
        musicUrl = try container.decodeIfPresent(String.self, forKey: .musicUrl)
        releaseDate = try container.decodeIfPresent(String.self, forKey: .releaseDate)
        explicit = try container.decodeIfPresent(Bool.self, forKey: .explicit)
        durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
        popularity = try container.decodeIfPresent(Int.self, forKey: .popularity)
        bpm = try container.decodeIfPresent(Int.self, forKey: .bpm)
        gain = try container.decodeIfPresent(Int.self, forKey: .gain)
        hasLyrics = try container.decodeIfPresent(Bool.self, forKey: .hasLyrics)
        momentUrl = try container.decodeIfPresent(String.self, forKey: .momentUrl)
        visibility = try container.decodeIfPresent(String.self, forKey: .visibility)
        likeCount = try container.decodeIfPresent(Int.self, forKey: .likeCount)
        saveCount = try container.decodeIfPresent(Int.self, forKey: .saveCount)
        shareCount = try container.decodeIfPresent(Int.self, forKey: .shareCount)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        owner = try container.decodeIfPresent(PlaylistProfileRef.self, forKey: .owner)
        artists = try container.decodeIfPresent([PlaylistTrackArtistRef].self, forKey: .artists)
        viewerContext = try container.decodeIfPresent(PlaylistTrackViewerContext.self, forKey: .viewerContext)
    }

    var primaryArtistName: String? {
        if let primary = artists?.first(where: { $0.isPrimary == true })?.artist {
            return primary.displayName ?? primary.username
        }
        if let first = artists?.first?.artist {
            return first.displayName ?? first.username
        }
        return owner?.displayName ?? owner?.username
    }

    func asNicheTrack() -> NicheTrack? {
        guard
            let musicUrl,
            !musicUrl.isEmpty,
            let artworkUrl,
            !artworkUrl.isEmpty,
            let durationMs
        else {
            return nil
        }

        let releaseDate = releaseDate ?? createdAt ?? ""
        let ownerProfile = owner ?? PlaylistProfileRef(
            id: ownerId,
            username: "unknown",
            displayName: nil,
            avatarUrl: nil,
            isVerified: nil,
            verificationType: nil
        )

        let fullOwner = FullUser(
            id: ownerProfile.id,
            username: ownerProfile.username,
            displayName: ownerProfile.displayName,
            avatarUrl: ownerProfile.avatarUrl,
            bio: nil,
            profileType: "user",
            typeUpdatedAt: "",
            createdAt: nil,
            updatedAt: nil,
            locationName: nil,
            isPrivate: false,
            isVerified: ownerProfile.isVerified ?? false,
            followersCount: 0,
            followingCount: 0,
            friendCount: 0,
            postsCount: 0,
            profileSongId: nil,
            profileSong: nil,
            spotifyAccount: nil,
            tiktokHandle: nil,
            instagramHandle: nil,
            allowMessagesFrom: nil,
            allowGroupInvites: nil,
            badges: nil
        )

        return NicheTrack(
            id: id,
            ownerId: ownerId,
            name: name,
            artworkUrl: artworkUrl,
            musicUrl: musicUrl,
            releaseDate: releaseDate,
            explicit: explicit ?? false,
            featuredDurations: nil,
            hasLyrics: hasLyrics ?? false,
            durationMs: durationMs,
            popularity: popularity ?? 0,
            bpm: bpm ?? 0,
            gain: gain ?? 0,
            createdAt: createdAt ?? "",
            updatedAt: updatedAt,
            deletedAt: nil,
            visibility: TrackVisiblity(rawValue: visibility ?? "public") ?? .public,
            likeCount: likeCount ?? 0,
            saveCount: saveCount ?? 0,
            shareCount: shareCount ?? 0,
            owner: fullOwner,
            momentUrl: momentUrl,
            credits: nil,
            metadata: nil
        )
    }
}

struct CreatePlaylistBody: Encodable {
    let name: String
    let description: String?
    let visibility: PlaylistVisibility
    let hasImage: Bool
    let format: String
}

struct UpdatePlaylistBody: Encodable {
    let name: String
    let description: String
    let visibility: PlaylistVisibility
    let hasImage: Bool
    let format: String
}

struct UpdatePlaylistResponse: Decodable {
    let playlist: PlaylistSummary
    let upload: PlaylistImageUploadInfo?
}

struct AddPlaylistItemBody: Encodable {
    let nicheTrackId: String
}

struct PlaylistAddItemResponse: Decodable {
    let item: PlaylistItem
}

struct PlaylistSuccessResponse: Decodable {
    let success: Bool
}

struct NicheTrackSearchArtist: Decodable, Equatable {
    let id: String
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let isVerified: Bool?
    let verificationType: String?
    let isPrimary: Bool?
}

struct NicheTrackSearchResult: Decodable, Identifiable, Equatable {
    let id: String
    let ownerId: String
    let name: String
    let artworkUrl: String?
    let musicUrl: String?
    let durationMs: Int?
    let explicit: Bool?
    let owner: PlaylistProfileRef?
    let artists: [NicheTrackSearchArtist]?
    let searchScore: Double?

    var primaryArtistName: String? {
        if let primary = artists?.first(where: { $0.isPrimary == true }) {
            return primary.displayName ?? primary.username
        }
        if let first = artists?.first {
            return first.displayName ?? first.username
        }
        return owner?.displayName ?? owner?.username
    }
}

struct NicheTrackSearchResponse: Decodable {
    let tracks: [NicheTrackSearchResult]
}

struct MovePlaylistItemBody: Encodable {
    let afterSortKey: Double?
    let beforeSortKey: Double?
}

struct MovePlaylistItemResponse: Decodable {
    let item: MovedPlaylistItemRow
}

struct MovedPlaylistItemRow: Decodable {
    let id: String
    let sortKey: Double
}

struct PlaylistImageUpdateBody: Encodable {
    let imageUrl: String
}

struct PlaylistImageUpdateResponse: Decodable {
    let playlist: PlaylistSummary?
}

extension PlaylistDetail {
    func withItems(_ items: [PlaylistItem], pagination: PlaylistPagination? = nil) -> PlaylistDetail {
        PlaylistDetail(
            id: id,
            ownerId: ownerId,
            name: name,
            description: description,
            visibility: visibility,
            imageUrl: imageUrl,
            createdAt: createdAt,
            updatedAt: updatedAt,
            trackCount: trackCount,
            saveCount: saveCount,
            shareCount: shareCount,
            owner: owner,
            items: items,
            pagination: pagination ?? self.pagination
        )
    }

    func applying(_ summary: PlaylistSummary) -> PlaylistDetail {
        PlaylistDetail(
            id: id,
            ownerId: ownerId,
            name: summary.name,
            description: summary.description,
            visibility: summary.visibility,
            imageUrl: summary.imageUrl,
            createdAt: createdAt,
            updatedAt: summary.updatedAt,
            trackCount: summary.trackCount ?? trackCount,
            saveCount: summary.saveCount ?? saveCount,
            shareCount: summary.shareCount ?? shareCount,
            owner: owner,
            items: items,
            pagination: pagination
        )
    }
}

extension PlaylistSummary {
    var displayTrackCount: Int {
        trackCount ?? 0
    }
}
