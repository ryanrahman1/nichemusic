//
//  PostModels.swift
//  nichemusic
//
//  Created by Ryan Rahman on 4/25/26.
//

import Foundation

enum PostKind: String, Decodable {
    case text
    case image
    case video
    case track
    case pmo
    case poll
}


enum PostVisibility: String, Codable {
    case `public`
    case `private`
    case group
}

struct PostMetadata: Decodable, Equatable {
    let layout: String?
    let source: String?
}

struct PostMedia: Decodable, Equatable {
    let url: String
    let kind: String
    let width: Int?
    let height: Int?
    let objectKey: String?
    let durationMs: Int?
}

struct TrackArtist: Decodable, Equatable {
    let id: String
    let name: String?
}

struct PostTrack: Decodable, Equatable {
    let id: String?
    let title: String
    let source: String?
    let albumId: String?
    let artistId: String?
    let sourceId: String?
    let artworkUrl: String?
    let previewUrl: String?
    let releaseDate: String?
    let artist: TrackArtist?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case name
        case source
        case albumId
        case artistId
        case sourceId
        case artworkUrl
        case previewUrl
        case releaseDate
        case artist
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id)
        let decodedTitle = try container.decodeIfPresent(String.self, forKey: .title)
        let decodedName = try container.decodeIfPresent(String.self, forKey: .name)
        title = decodedTitle ?? decodedName ?? ""
        source = try container.decodeIfPresent(String.self, forKey: .source)
        albumId = try container.decodeIfPresent(String.self, forKey: .albumId)
        artistId = try container.decodeIfPresent(String.self, forKey: .artistId)
        sourceId = try container.decodeIfPresent(String.self, forKey: .sourceId)
        artworkUrl = try container.decodeIfPresent(String.self, forKey: .artworkUrl)
        previewUrl = try container.decodeIfPresent(String.self, forKey: .previewUrl)
        releaseDate = try container.decodeIfPresent(String.self, forKey: .releaseDate)
        artist = try container.decodeIfPresent(TrackArtist.self, forKey: .artist)
    }
}



struct PostTemplate: Decodable, Equatable {
    let name: String?
    let data: PostTemplateData?
}

struct PostTemplateData: Decodable, Equatable {
    let prompt: String?
    let allowTrackReplies: Bool?
}

struct PostAnalytics: Decodable, Equatable {
    let hasMedia: Bool?
    let hasTrack: Bool?
    let mediaCount: Int?
    let hasOriginalSound: Bool?
}

struct PostOriginalSound: Decodable, Equatable {
    let kind: String?
    let source: String?
}

struct PostNicheTrackOwner: Decodable, Equatable {
    let id: String
    let username: String
    let avatarUrl: String?
    let profileType: String?
    let typeUpdatedAt: String?
}

struct PostNicheTrack: Decodable, Equatable {
    let id: String
    let title: String?
    let name: String?
    let artworkUrl: String?
    let musicUrl: String?
    let momentUrl: String?
    let durationMs: Int?
    let explicit: Bool?
    let releaseDate: String?
    let ownerId: String?
    let ownerUsername: String?
    let owner: PostNicheTrackOwner?

    var displayTitle: String {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedTitle.isEmpty { return trimmedTitle }
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedName.isEmpty { return trimmedName }
        return "Track"
    }

    var displayArtistName: String {
        if let username = owner?.username, !username.isEmpty { return username }
        if let ownerUsername, !ownerUsername.isEmpty { return ownerUsername }
        return ""
    }

    var resolvedArtworkURL: URL? {
        guard let artworkUrl else { return nil }
        let resolved = artworkUrl
            .replacingOccurrences(of: "{w}x{h}", with: "1000x1000")
            .replacingOccurrences(of: "{w}", with: "1000")
            .replacingOccurrences(of: "{h}", with: "1000")
        return URL(string: resolved)
    }

    var isMomentVideo: Bool {
        guard let momentUrl, !momentUrl.isEmpty else { return false }
        return URL(string: momentUrl) != nil
    }
}

struct PostContent: Decodable, Equatable {
    let kind: PostKind
    let caption: String?
    let metadata: PostMetadata?
    let media: [PostMedia]?
    let track: PostTrack?
    let nicheTrack: PostNicheTrack?
    let version: Int?
    let template: PostTemplate?
    let analytics: PostAnalytics?
    let originalSound: PostOriginalSound?
}


extension Post {
    var asFeedItem: FeedItem {
        let resolvedCatalogTrack = track ?? content.track
        let resolvedNicheTrack = nicheTrack ?? content.nicheTrack

        return FeedItem(
            type: "post",
            post: FeedPost(
                id: id,
                ownerId: ownerId,
                groupId: groupId,
                kind: kind.rawValue,
                trackId: trackId,
                nicheTrackId: nicheTrackId,
                visibility: visibility.rawValue,
                likeCount: likeCount,
                repostCount: repostCount,
                commentCount: commentCount,
                viewCount: viewCount,
                createdAt: createdAt,
                updatedAt: updatedAt,
                content: FeedPostContent(
                    kind: content.kind.rawValue,
                    media: content.media?.map {
                        FeedMedia(
                            url: $0.url,
                            kind: $0.kind,
                            width: $0.width,
                            height: $0.height,
                            objectKey: $0.objectKey,
                            durationMs: $0.durationMs
                        )
                    },
                    track: resolvedCatalogTrack.map {
                        FeedContentTrack(
                            id: $0.id,
                            title: $0.title,
                            name: $0.title,
                            source: $0.source,
                            albumId: $0.albumId,
                            artistId: $0.artistId,
                            sourceId: $0.sourceId,
                            artistName: $0.artist?.name,
                            artworkUrl: $0.artworkUrl,
                            previewUrl: $0.previewUrl,
                            releaseDate: $0.releaseDate
                        )
                    },
                    nicheTrack: resolvedNicheTrack,
                    caption: content.caption,
                    version: content.version,
                    metadata: content.metadata.map {
                        FeedContentMetadata(layout: $0.layout, source: $0.source)
                    },
                    template: content.template.map {
                        FeedTemplate(
                            name: $0.name,
                            data: $0.data.map {
                                FeedTemplateData(
                                    prompt: $0.prompt,
                                    allowTrackReplies: $0.allowTrackReplies
                                )
                            }
                        )
                    },
                    analytics: content.analytics.map {
                        FeedAnalytics(
                            hasMedia: $0.hasMedia,
                            hasTrack: $0.hasTrack,
                            mediaCount: $0.mediaCount,
                            hasOriginalSound: $0.hasOriginalSound
                        )
                    },
                    originalSound: content.originalSound.map {
                        FeedOriginalSound(kind: $0.kind, source: $0.source)
                    }
                ),
                hasMedia: hasMedia,
                hasTrack: hasTrack,
                hasSound: hasSound,
                shareCount: shareCount,
                owner: FeedOwner(
                    id: owner.id,
                    username: owner.username,
                    avatarUrl: owner.avatarUrl,
                    profileType: owner.profileType,
                    typeUpdatedAt: owner.typeUpdatedAt
                ),
                group: group.map {
                    FeedGroup(id: $0.id, name: $0.name)
                },
                track: resolvedCatalogTrack.map {
                    FeedTrack(
                        id: $0.id ?? trackId ?? id,
                        name: $0.title,
                        artist: FeedArtist(
                            id: $0.artistId ?? "",
                            name: $0.artist?.name ?? ""
                        ),
                        source: $0.source ?? "apple_music",
                        sourceId: $0.sourceId,
                        artworkUrl: $0.artworkUrl,
                        previewUrl: $0.previewUrl
                    )
                },
                nicheTrack: resolvedNicheTrack
            ),
            viewer: FeedViewer(isLiked: false, isReposted: false)
        )
    }
}
