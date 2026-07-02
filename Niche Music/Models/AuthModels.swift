//
//  AuthModels.swift
//  nichemusic
//
//  Created by Ryan Rahman on 4/25/26.
//

import Foundation

struct User: Decodable, Equatable {
    let id: String
    let avatarUrl: String
    let email: String?

    init(id: String, avatarUrl: String, email: String? = nil) {
        self.id = id
        self.avatarUrl = avatarUrl
        self.email = email
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case avatarUrl
        case email
    }
}

#if DEBUG
extension User {
    static let preview = User(
        id: "C9Qgjii52AND2kArKc0G6Q",
        avatarUrl: "https://cdn.nichemusic.app/avatars/cqXcxocvtYdEFnoDppneHg/avatar-cAZ-xSAdwUSalGao.jpg"
    )
}
#endif

struct SessionResponse: Decodable {
    let user: User
    let emailVerified: Bool?
}

struct EmailVerifySendResponse: Decodable {
    let sent: Bool?
    let alreadyVerified: Bool?
    let expiresAt: String?
    let cooldownSeconds: Int?
}

struct EmailVerifyConfirmBody: Encodable {
    let code: String
}

struct EmailVerifyConfirmResponse: Decodable {
    let verified: Bool?
    let alreadyVerified: Bool?
}

struct PasswordResetSendBody: Encodable {
    let email: String
}

struct PasswordResetSendResponse: Decodable {
    let sent: Bool?
}

struct LoginBody: Encodable {
    let email: String
    let password: String
}

struct SignupBody: Encodable {
    let email: String
    let password: String
    let username: String
    let profileType: String
    let choseAvatar: Bool
}

struct SignupResponse: Decodable {
    let user: SignupUserRef
    let avatarUpload: AvatarUploadInfo?
}

struct SignupUserRef: Decodable {
    let id: String
    let avatarUrl: String?
}

struct UsernameAvailabilityResponse: Decodable {
    let available: Bool
    let reason: String?
    let message: String?
}

struct ProfileBadge: Decodable, Equatable, Identifiable {
    let id: String
    let text: String
    let colorHex: String
    let createdAt: String?
}

struct ProfileBadgeSlot: Decodable, Equatable {
    let badge: ProfileBadge
    let index: Int
}

struct ProfileTrackArtist: Decodable, Equatable {
    let name: String
}

struct ProfileSong: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let artist: ProfileTrackArtist
    let source: String?
    let sourceId: String?
    let artworkUrl: String?
    let previewUrl: String?

    var resolvedArtworkURL: URL? {
        guard let artworkUrl else { return nil }

        let resolved = artworkUrl
            .replacingOccurrences(of: "{w}x{h}", with: "120x120")
            .replacingOccurrences(of: "{w}", with: "120")
            .replacingOccurrences(of: "{h}", with: "120")

        return URL(string: resolved)
    }

    var appleMusicURL: URL? {
        guard source == "apple_music", let sourceId else { return nil }
        return URL(string: "music://music.apple.com/us/song/\(sourceId)")
    }
}

struct FullUser: Decodable, Equatable {
    let id: String
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let profileType: String
    let typeUpdatedAt: String
    let bio: String?
    let createdAt: String?
    let updatedAt: String?
    let locationName: String?
    let isPrivate: Bool
    let isVerified: Bool
    let followersCount: Int
    let followingCount: Int
    let friendCount: Int
    let postsCount: Int
    let profileSongId: String?
    let profileSong: ProfileSong?
    let spotifyAccount: String?
    let tiktokHandle: String?
    let instagramHandle: String?
    let allowMessagesFrom: String?
    let allowGroupInvites: Bool?
    let badges: [ProfileBadgeSlot]?

    var sortedBadges: [ProfileBadge] {
        (badges ?? [])
            .sorted { $0.index < $1.index }
            .map(\.badge)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName
        case avatarUrl
        case profileType
        case typeUpdatedAt
        case bio
        case createdAt
        case updatedAt
        case locationName
        case isPrivate
        case isVerified
        case followersCount
        case followingCount
        case friendCount
        case postsCount
        case profileSongId
        case profileSong
        case spotifyAccount
        case tiktokHandle
        case instagramHandle
        case allowMessagesFrom
        case allowGroupInvites
        case badges
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        profileType = try container.decode(String.self, forKey: .profileType)
        typeUpdatedAt = try container.decode(String.self, forKey: .typeUpdatedAt)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        locationName = try container.decodeIfPresent(String.self, forKey: .locationName)
        isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        isVerified = try container.decodeIfPresent(Bool.self, forKey: .isVerified) ?? false
        followersCount = try container.decodeIfPresent(Int.self, forKey: .followersCount) ?? 0
        followingCount = try container.decodeIfPresent(Int.self, forKey: .followingCount) ?? 0
        friendCount = try container.decodeIfPresent(Int.self, forKey: .friendCount) ?? 0
        postsCount = try container.decodeIfPresent(Int.self, forKey: .postsCount) ?? 0
        profileSongId = try container.decodeIfPresent(String.self, forKey: .profileSongId)
        profileSong = try container.decodeIfPresent(ProfileSong.self, forKey: .profileSong)
        spotifyAccount = try container.decodeIfPresent(String.self, forKey: .spotifyAccount)
        tiktokHandle = try container.decodeIfPresent(String.self, forKey: .tiktokHandle)
        instagramHandle = try container.decodeIfPresent(String.self, forKey: .instagramHandle)
        allowMessagesFrom = try container.decodeIfPresent(String.self, forKey: .allowMessagesFrom)
        allowGroupInvites = try container.decodeIfPresent(Bool.self, forKey: .allowGroupInvites)
        badges = try container.decodeIfPresent([ProfileBadgeSlot].self, forKey: .badges)
    }

    init(
        id: String,
        username: String,
        displayName: String?,
        avatarUrl: String?,
        bio: String?,
        profileType: String,
        typeUpdatedAt: String,
        createdAt: String?,
        updatedAt: String?,
        locationName: String?,
        isPrivate: Bool,
        isVerified: Bool,
        followersCount: Int,
        followingCount: Int,
        friendCount: Int,
        postsCount: Int,
        profileSongId: String?,
        profileSong: ProfileSong?,
        spotifyAccount: String?,
        tiktokHandle: String?,
        instagramHandle: String?,
        allowMessagesFrom: String?,
        allowGroupInvites: Bool?,
        badges: [ProfileBadgeSlot]?
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.bio = bio
        self.profileType = profileType
        self.typeUpdatedAt = typeUpdatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.locationName = locationName
        self.isPrivate = isPrivate
        self.isVerified = isVerified
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.friendCount = friendCount
        self.postsCount = postsCount
        self.profileSongId = profileSongId
        self.profileSong = profileSong
        self.spotifyAccount = spotifyAccount
        self.tiktokHandle = tiktokHandle
        self.instagramHandle = instagramHandle
        self.allowMessagesFrom = allowMessagesFrom
        self.allowGroupInvites = allowGroupInvites
        self.badges = badges
    }
}

struct MeResponse: Decodable {
    let user: FullUser
}

struct ProfileViewerContext: Decodable, Equatable {
    let isSelf: Bool
    let isFollowing: Bool?
    let isFollowedBy: Bool
    let isBlocked: Bool
    let isBlockedBy: Bool
    let outgoingFollowRequest: Bool
    let incomingFollowRequest: Bool
}

struct UserProfileResponse: Decodable {
    let user: FullUser
    let viewer: ProfileViewerContext?
}


