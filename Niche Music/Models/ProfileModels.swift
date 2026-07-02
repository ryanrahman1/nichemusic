//
//  ProfileModels.swift
//  nichemusic
//
//  Created by Ryan Rahman on 4/25/26.
//

import Foundation

// MARK: - Placeholder Models

struct ProfileRepost: Identifiable, Equatable, Decodable {
    let id: String
    let post: ProfilePost
    let originalUsername: String
}

struct LibraryTrack: Identifiable {
    let id: String
    let name: String
    let artworkUrl: String?
}

struct LibraryAlbum: Identifiable {
    let id: String
    let name: String
    let artworkUrl: String?
}

struct LibraryArtist: Identifiable {
    let id: String
    let name: String
    let imageUrl: String?
}
///


struct ProfilePostOwner: Decodable, Equatable {
    let id: String
    let username: String
    let avatarUrl: String?
    let profileType: String?
    let typeUpdatedAt: String?
}

struct ProfilePostGroup: Decodable, Equatable {
    let id: String
    let name: String
}


struct ProfilePost: Decodable, Equatable, Identifiable {
    let id: String
    let ownerId: String
    let groupId: String?
    let kind: PostKind
    let trackId: String?
    let nicheTrackId: String?
    let visibility: PostVisibility
    let likeCount: Int
    let repostCount: Int
    let commentCount: Int
    let viewCount: Int
    let shareCount: Int
    let createdAt: String
    let updatedAt: String?
    let hasMedia: Bool
    let hasTrack: Bool
    let hasSound: Bool
    let owner: ProfilePostOwner
    let group: ProfilePostGroup?
    let content: PostContent
    let track: PostTrack?
    let nicheTrack: PostNicheTrack?
}

struct ProfilePosts: Decodable, Equatable {
    let posts: [ProfilePost]
    let nextCursor: String?
    let hasMore: Bool
    let limit: Int

    static let empty = ProfilePosts(
        posts: [],
        nextCursor: nil,
        hasMore: false,
        limit: 20
    )
}

struct ProfilePostsResponse: Decodable, Equatable {
    let posts: [ProfilePost]
}

struct ProfilePostsCursor: Codable, Equatable {
    let cursorCreatedAt: String
    let cursorId: String

    init?(rawValue: String?) {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ProfilePostsCursor.self, from: data) else {
            return nil
        }

        self = decoded
    }

    var rawValue: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct ProfilePostsPage: Equatable {
    let requestCursor: String?
    let posts: [ProfilePost]
    let nextCursor: String?
    let hasMore: Bool
    let limit: Int
    let fetchedAt: Date
}

struct ProfileRepostViewer: Decodable, Equatable {
    let isLiked: Bool?
    let isReposted: Bool?
}

struct ProfileRepostRow: Decodable, Equatable, Identifiable {
    let reposterId: String
    let postId: String
    let createdAt: String
    let post: ProfilePost
    let viewer: ProfileRepostViewer?

    var id: String {
        "\(postId)_\(createdAt)"
    }
}

struct ProfileRepostsResponse: Decodable, Equatable {
    let posts: [ProfileRepostRow]
}

struct ProfileReposts: Decodable, Equatable {
    let reposts: [ProfileRepost]
    let nextCursor: String?
    let hasMore: Bool
    let limit: Int

    static let empty = ProfileReposts(
        reposts: [],
        nextCursor: nil,
        hasMore: false,
        limit: 20
    )
}

struct ProfileRepostsPage: Equatable, Decodable {
    let requestCursor: String?
    let reposts: [ProfileRepost]
    let nextCursor: String?
    let hasMore: Bool
    let limit: Int
    let fetchedAt: Date
}

struct ProfileMusicSongViewer: Decodable, Equatable {
    let isLiked: Bool?
    let isSaved: Bool?
}

struct ProfileMusicSong: Decodable, Equatable {
    let id: String
    let name: String
    let source: String
    let albumId: String?
    let artistId: String
    let sourceId: String
    let artworkUrl: String?
    let artistName: String?
    let viewer: ProfileMusicSongViewer?
}

struct ProfileMusicSongResponse: Decodable, Equatable {
    let songs: [ProfileMusicSong]
}

struct ProfileFollowingArtist: Decodable, Equatable {
    let id: String
    let name: String
    let source: String
    let sourceId: String?
    let ownerId: String?
    let imageUrl: String?
}

struct ProfileFollowingArtistResponse: Decodable, Equatable {
    let artists: [ProfileFollowingArtist]
}

struct ProfileMusicSongPage: Equatable {
    let requestCursor: String?
    let songs: [ProfileMusicSong]
    let nextCursor: String?
    let hasMore: Bool
    let limit: Int
    let fetchedAt: Date
}

struct ProfileFollowingArtistPage: Equatable {
    let requestCursor: String?
    let artists: [ProfileFollowingArtist]
    let nextCursor: String?
    let hasMore: Bool
    let limit: Int
    let fetchedAt: Date
}

struct OtherProfileData: Equatable {
    var user: FullUser?
    var viewer: ProfileViewerContext?
    var posts: ProfilePosts?
    var reposts: ProfileReposts?
    var likedSongs: [ProfileMusicSong] = []
    var followingArtists: [ProfileFollowingArtist] = []
    var discographyByFilter: [String: ProfileDiscographyCollection] = [:]
    var errorMessage: String?
    var profileLoadedAt: Date?
    var postsLoadedAt: Date?
    var repostsLoadedAt: Date?
    var musicLoadedAt: Date?
    var discographyLoadedAt: Date?
}

enum ProfileDiscographyFilter: String, CaseIterable, Identifiable, Equatable {
    case all = "All"
    case album = "Albums"
    case single = "Singles"
    case featuredOn = "Featured On"

    var id: String { rawValue }

    var apiValue: String {
        switch self {
        case .all: return "all"
        case .album: return "album"
        case .single: return "single"
        case .featuredOn: return "featured_on"
        }
    }

    static func from(apiValue: String) -> ProfileDiscographyFilter? {
        switch apiValue {
        case "all": return .all
        case "album": return .album
        case "single": return .single
        case "featured_on": return .featuredOn
        default: return nil
        }
    }
}

struct ProfileDiscographyItem: Decodable, Equatable, Identifiable {
    let id: String
    let title: String
    let releaseDate: String
    let imageUrl: String?
    let type: String

    var formattedType: String {
        switch type {
        case "album": return "Album"
        case "ep": return "EP"
        case "single": return "Single"
        case "featured_on": return "Featured On"
        default: return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var isReleaseCollection: Bool {
        type == "album" || type == "ep"
    }

    var subtitle: String {
        let year = String(releaseDate.prefix(4))
        return "\(formattedType) • \(year)"
    }

    func resolvedImageURL(size: Int = 120) -> URL? {
        guard let imageUrl, !imageUrl.isEmpty else { return nil }
        if imageUrl.contains("{w}") || imageUrl.contains("{h}") {
            return resolvedAppleArtworkURL(imageUrl, size: size)
        }
        return URL(string: imageUrl)
    }
}

struct ProfileDiscographyResponse: Decodable, Equatable {
    let latestRelease: ProfileDiscographyItem?
    let items: [ProfileDiscographyItem]

    enum CodingKeys: String, CodingKey {
        case latestRelease = "latest_release"
        case items
    }
}

struct ProfileDiscographyCursor: Codable, Equatable {
    let cursorReleaseDate: String
    let cursorType: String
    let cursorId: String

    init?(rawValue: String?) {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ProfileDiscographyCursor.self, from: data) else {
            return nil
        }

        self = decoded
    }

    var rawValue: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct ProfileDiscographyPage: Equatable {
    let requestCursor: String?
    let filter: ProfileDiscographyFilter
    let latestRelease: ProfileDiscographyItem?
    let items: [ProfileDiscographyItem]
    let nextCursor: String?
    let hasMore: Bool
    let limit: Int
    let fetchedAt: Date
}

struct ProfileDiscographyCollection: Equatable {
    var latestRelease: ProfileDiscographyItem?
    var items: [ProfileDiscographyItem]
    var nextCursor: String?
    var hasMore: Bool
    var limit: Int

    static let empty = ProfileDiscographyCollection(
        latestRelease: nil,
        items: [],
        nextCursor: nil,
        hasMore: false,
        limit: 20
    )
}

extension ProfilePost {
    var asPost: Post {
        Post(
            id: id,
            ownerId: ownerId,
            groupId: groupId,
            kind: kind,
            trackId: trackId,
            nicheTrackId: nicheTrackId,
            visibility: visibility,
            likeCount: likeCount,
            repostCount: repostCount,
            commentCount: commentCount,
            viewCount: viewCount,
            shareCount: shareCount,
            createdAt: createdAt,
            updatedAt: updatedAt,
            content: content,
            hasMedia: hasMedia,
            hasTrack: hasTrack,
            hasSound: hasSound,
            owner: PostOwner(
                id: owner.id,
                username: owner.username,
                avatarUrl: owner.avatarUrl,
                profileType: owner.profileType,
                typeUpdatedAt: owner.typeUpdatedAt
            ),
            group: group.map { PostGroup(id: $0.id, name: $0.name) },
            track: track,
            nicheTrack: nicheTrack
        )
    }
}
