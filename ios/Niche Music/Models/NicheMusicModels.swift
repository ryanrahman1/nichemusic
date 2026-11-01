//
//  NicheMusicModels.swift
//  nichemusic
//
//  Created by Ryan Rahman on 5/9/26.
//

// models for niche music tracks

enum TrackVisiblity: String, Decodable {
    case `public`
    case `private`
}

struct TrackViewer: Decodable, Equatable {
    let isLiked: Bool
    let isSaved: Bool
}

struct NicheTrackCreditArtist: Decodable, Equatable {
    let id: String
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let isVerified: Bool?
    let profileType: String?
    let typeUpdatedAt: String?
}

struct NicheTrackCredit: Decodable, Equatable {
    let trackId: String?
    let artistId: String?
    let isPrimary: Bool?
    let artist: NicheTrackCreditArtist?
}

struct NicheTrackMetadata: Decodable, Equatable {
    let mood: String?
    let energy: Int?
    let danceability: Int?
    let valence: Int?
    let intensity: Int?
    let topics: [String]?
    let language: String?
    let explicitScore: Int?
    let extra: [String: String]?

    enum CodingKeys: String, CodingKey {
        case mood
        case energy
        case danceability
        case valence
        case intensity
        case topics
        case language
        case explicitScore = "explicit_score"
        case extra = "metadata"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mood = try container.decodeIfPresent(String.self, forKey: .mood)
        energy = try container.decodeIfPresent(Int.self, forKey: .energy)
        danceability = try container.decodeIfPresent(Int.self, forKey: .danceability)
        valence = try container.decodeIfPresent(Int.self, forKey: .valence)
        intensity = try container.decodeIfPresent(Int.self, forKey: .intensity)
        topics = try container.decodeIfPresent([String].self, forKey: .topics)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        explicitScore = try container.decodeIfPresent(Int.self, forKey: .explicitScore)
        extra = Self.decodeStringDictionary(from: container, forKey: .extra)
    }

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }

    private static func decodeStringDictionary(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> [String: String]? {
        guard container.contains(key) else { return nil }

        if let dictionary = try? container.decode([String: String].self, forKey: key) {
            return dictionary.isEmpty ? nil : dictionary
        }

        guard let nested = try? container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: key) else {
            return nil
        }

        var mapped: [String: String] = [:]
        for codingKey in nested.allKeys {
            if let string = try? nested.decode(String.self, forKey: codingKey) {
                mapped[codingKey.stringValue] = string
            } else if let int = try? nested.decode(Int.self, forKey: codingKey) {
                mapped[codingKey.stringValue] = String(int)
            } else if let double = try? nested.decode(Double.self, forKey: codingKey) {
                mapped[codingKey.stringValue] = String(double)
            } else if let bool = try? nested.decode(Bool.self, forKey: codingKey) {
                mapped[codingKey.stringValue] = bool ? "true" : "false"
            }
        }

        return mapped.isEmpty ? nil : mapped
    }
}

struct NicheTrack: Decodable, Equatable {
    let id: String
    let ownerId: String
    let name: String
    let artworkUrl: String
    let musicUrl: String // actual music url
    let releaseDate: String
    let explicit: Bool
    let featuredDurations: [String: Int]? // map of feature name to duration in seconds
    let hasLyrics: Bool
    let durationMs: Int
    let popularity: Int
    let bpm: Int
    let gain: Int
    let createdAt: String
    let updatedAt: String?
    let deletedAt: String?
    let visibility: TrackVisiblity
    let likeCount: Int
    let saveCount: Int
    let shareCount: Int
    let owner: FullUser
    let momentUrl: String?
    let credits: [NicheTrackCredit]?
    let metadata: NicheTrackMetadata?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId
        case name
        case artworkUrl
        case musicUrl
        case releaseDate
        case explicit
        case featuredDurations
        case hasLyrics
        case durationMs
        case popularity
        case bpm
        case gain
        case createdAt
        case updatedAt
        case deletedAt
        case visibility
        case likeCount
        case saveCount
        case shareCount
        case owner
        case momentUrl
        case credits
        case metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        ownerId = try container.decode(String.self, forKey: .ownerId)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        artworkUrl = try container.decodeIfPresent(String.self, forKey: .artworkUrl) ?? ""
        musicUrl = try container.decodeIfPresent(String.self, forKey: .musicUrl) ?? ""
        releaseDate = Self.decodeString(from: container, forKey: .releaseDate) ?? ""
        explicit = try container.decodeIfPresent(Bool.self, forKey: .explicit) ?? false
        featuredDurations = try container.decodeIfPresent([String: Int].self, forKey: .featuredDurations)
        hasLyrics = try container.decodeIfPresent(Bool.self, forKey: .hasLyrics) ?? false
        durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs) ?? 0
        popularity = try container.decodeIfPresent(Int.self, forKey: .popularity) ?? 0
        bpm = try container.decodeIfPresent(Int.self, forKey: .bpm) ?? 0
        gain = Self.decodeInt(from: container, forKey: .gain) ?? 0
        createdAt = Self.decodeString(from: container, forKey: .createdAt) ?? ""
        updatedAt = Self.decodeString(from: container, forKey: .updatedAt)
        deletedAt = Self.decodeString(from: container, forKey: .deletedAt)
        visibility = (try? container.decode(TrackVisiblity.self, forKey: .visibility)) ?? .public
        likeCount = try container.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        saveCount = try container.decodeIfPresent(Int.self, forKey: .saveCount) ?? 0
        shareCount = try container.decodeIfPresent(Int.self, forKey: .shareCount) ?? 0
        owner = try container.decode(FullUser.self, forKey: .owner)
        momentUrl = try container.decodeIfPresent(String.self, forKey: .momentUrl)
        credits = try container.decodeIfPresent([NicheTrackCredit].self, forKey: .credits)
        metadata = Self.decodeMetadata(from: container)
    }

    init(
        id: String,
        ownerId: String,
        name: String,
        artworkUrl: String,
        musicUrl: String,
        releaseDate: String,
        explicit: Bool,
        featuredDurations: [String: Int]?,
        hasLyrics: Bool,
        durationMs: Int,
        popularity: Int,
        bpm: Int,
        gain: Int,
        createdAt: String,
        updatedAt: String?,
        deletedAt: String?,
        visibility: TrackVisiblity,
        likeCount: Int,
        saveCount: Int,
        shareCount: Int,
        owner: FullUser,
        momentUrl: String?,
        credits: [NicheTrackCredit]? = nil,
        metadata: NicheTrackMetadata? = nil
    ) {
        self.id = id
        self.ownerId = ownerId
        self.name = name
        self.artworkUrl = artworkUrl
        self.musicUrl = musicUrl
        self.releaseDate = releaseDate
        self.explicit = explicit
        self.featuredDurations = featuredDurations
        self.hasLyrics = hasLyrics
        self.durationMs = durationMs
        self.popularity = popularity
        self.bpm = bpm
        self.gain = gain
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.visibility = visibility
        self.likeCount = likeCount
        self.saveCount = saveCount
        self.shareCount = shareCount
        self.owner = owner
        self.momentUrl = momentUrl
        self.credits = credits
        self.metadata = metadata
    }

    private static func decodeString(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> String? {
        if let value = try? container.decode(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        return nil
    }

    private static func decodeInt(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Double.self, forKey: key) {
            return Int(value.rounded())
        }
        return nil
    }

    private static func decodeMetadata(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> NicheTrackMetadata? {
        if let metadata = try? container.decode(NicheTrackMetadata.self, forKey: .metadata) {
            return metadata
        }
        if let metadataItems = try? container.decode([NicheTrackMetadata].self, forKey: .metadata) {
            return metadataItems.first
        }
        return nil
    }
}

struct NicheTrackResponse: Decodable, Equatable {
    let track: NicheTrack
    let viewer: TrackViewer?
}

struct TrackLyrics: Decodable {
    let trackId: String
    let originalLanguage: String
    let isSynced: Bool
    let hasTranslation: Bool
    let lyricsJson: [LyricLine]
    let plainText: String
    let updatedAt: String
}

struct LyricLine: Decodable, Identifiable {
    let e: String  // english/display text
    let o: String  // original text
    let t: Int     // timestamp in milliseconds

    var id: Int { t }
    var timeSeconds: Double { Double(t) / 1000.0 }
}

struct TrackLyricsResponse: Decodable {
    let lyrics: TrackLyrics
}

struct TrackCommentsResponse: Decodable, Equatable {
    let comments: [TrackComment]
}

struct TrackComment: Decodable, Equatable, Identifiable {
    let id: String
    let trackId: String
    let ownerId: String
    let parentCommentId: String?
    let replyToCommentId: String?
    let replyToUserId: String?
    let kind: TrackCommentKind
    let content: TrackCommentContent
    var likeCount: Int
    var replyCount: Int
    var isHidden: Bool
    var isPinned: Bool
    let createdAt: String
    let deletedAt: String?
    let owner: TrackCommentOwner
    let replyToUser: TrackCommentOwner?
    var viewer: TrackCommentViewer?

    enum CodingKeys: String, CodingKey {
        case id
        case trackId
        case postId
        case ownerId
        case parentCommentId
        case replyToCommentId
        case replyToUserId
        case kind
        case content
        case likeCount
        case replyCount
        case isHidden
        case isPinned
        case createdAt
        case deletedAt
        case owner
        case replyToUser
        case viewer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        trackId = try container.decodeIfPresent(String.self, forKey: .trackId)
            ?? container.decode(String.self, forKey: .postId)
        ownerId = try container.decode(String.self, forKey: .ownerId)
        parentCommentId = try container.decodeIfPresent(String.self, forKey: .parentCommentId)
        replyToCommentId = try container.decodeIfPresent(String.self, forKey: .replyToCommentId)
        replyToUserId = try container.decodeIfPresent(String.self, forKey: .replyToUserId)
        kind = try container.decode(TrackCommentKind.self, forKey: .kind)
        content = try container.decode(TrackCommentContent.self, forKey: .content)
        likeCount = try container.decode(Int.self, forKey: .likeCount)
        replyCount = try container.decode(Int.self, forKey: .replyCount)
        isHidden = try container.decode(Bool.self, forKey: .isHidden)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
        owner = try container.decode(TrackCommentOwner.self, forKey: .owner)
        replyToUser = try container.decodeIfPresent(TrackCommentOwner.self, forKey: .replyToUser)
        viewer = try container.decodeIfPresent(TrackCommentViewer.self, forKey: .viewer)
    }
}

extension TrackComment: Hashable {
    static func == (lhs: TrackComment, rhs: TrackComment) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum TrackCommentKind: String, Decodable, Equatable {
    case text
    case gif
    case track
}

struct TrackCommentOwner: Decodable, Equatable {
    let id: String
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let isVerified: Bool?
    let profileType: String?
    let typeUpdatedAt: String?
}

struct TrackCommentViewer: Decodable, Equatable {
    var isLiked: Bool?
    var isOwner: Bool?
}

struct TrackCommentContent: Decodable, Equatable {
    let kind: TrackCommentKind
    let text: String?
    let version: Int?
    let gif: TrackCommentGif?
    let track: TrackCommentSharedTrack?
}

struct TrackCommentGif: Decodable, Equatable {
    let id: String
    let url: String
    let width: Int?
    let height: Int?
}

struct TrackCommentSharedTrack: Decodable, Equatable {
    let id: String
    let title: String
    let source: String?
    let albumId: String?
    let artistId: String?
    let sourceId: String?
    let artistName: String?
    let artworkUrl: String?
    let previewUrl: String?
    let releaseDate: String?
}
