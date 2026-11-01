//
//  ProfileUpdateModels.swift
//  Niche Music
//

import Foundation

enum AllowMessagesFrom: String, CaseIterable, Identifiable {
    case all
    case followers
    case friends
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "Everyone"
        case .followers: "Followers"
        case .friends: "Friends"
        case .none: "No one"
        }
    }
}

/// PATCH body keys match `POST /me/update` schema (mixed camelCase / snake_case).
struct UpdateProfileBody: Encodable {
    var displayName: String?
    var bio: String?
    var locationName: String?
    var isPrivate: Bool?
    var profileSongId: String?
    var profileType: String?
    var allowMessagesFrom: String?
    var allowGroupInvites: Bool?
    var spotifyAccount: String?
    var instagramHandle: String?
    var tiktokHandle: String?
    var updateAvatar: Bool?

    enum CodingKeys: String, CodingKey {
        case displayName
        case bio
        case location_name
        case is_private
        case profile_song_id
        case profile_type
        case allow_messages_from
        case allow_group_invites
        case spotify_account
        case instagram_handle
        case tiktok_handle
        case update_avatar
    }

    var isEmpty: Bool {
        displayName == nil
            && bio == nil
            && locationName == nil
            && isPrivate == nil
            && profileSongId == nil
            && profileType == nil
            && allowMessagesFrom == nil
            && allowGroupInvites == nil
            && spotifyAccount == nil
            && instagramHandle == nil
            && tiktokHandle == nil
            && updateAvatar != true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let displayName { try container.encode(displayName, forKey: .displayName) }
        if let bio { try container.encode(bio, forKey: .bio) }
        if let locationName { try container.encode(locationName, forKey: .location_name) }
        if let isPrivate { try container.encode(isPrivate, forKey: .is_private) }
        if let profileSongId { try container.encode(profileSongId, forKey: .profile_song_id) }
        if let profileType { try container.encode(profileType, forKey: .profile_type) }
        if let allowMessagesFrom { try container.encode(allowMessagesFrom, forKey: .allow_messages_from) }
        if let allowGroupInvites { try container.encode(allowGroupInvites, forKey: .allow_group_invites) }
        if let spotifyAccount { try container.encode(spotifyAccount, forKey: .spotify_account) }
        if let instagramHandle { try container.encode(instagramHandle, forKey: .instagram_handle) }
        if let tiktokHandle { try container.encode(tiktokHandle, forKey: .tiktok_handle) }
        if updateAvatar == true { try container.encode(true, forKey: .update_avatar) }
    }
}

struct ProfileUpdateResponse: Decodable {
    let user: ProfileUpdateUserRef
    let avatarUpload: AvatarUploadInfo?
}

struct ProfileUpdateUserRef: Decodable {
    let id: String
}

struct AvatarUploadInfo: Decodable {
    let uploadUrl: String
    let avatarUrl: String
    let objectKey: String
    let contentType: String
    let maxBytes: Int
}

struct ConfirmAvatarBody: Encodable {
    let objectKey: String
    let avatarUrl: String
}

struct EditProfileDraft: Equatable {
    var displayName: String
    var bio: String
    var locationName: String
    var isPrivate: Bool
    var profileSongId: String
    var profileType: ProfileType
    var allowMessagesFrom: AllowMessagesFrom
    var allowGroupInvites: Bool
    var spotifyAccount: String
    var instagramHandle: String
    var tiktokHandle: String

    static func from(user: FullUser) -> EditProfileDraft {
        EditProfileDraft(
            displayName: user.displayName ?? "",
            bio: user.bio ?? "",
            locationName: user.locationName ?? "",
            isPrivate: user.isPrivate,
            profileSongId: user.profileSongId ?? "",
            profileType: ProfileType.fromStored(user.profileType),
            allowMessagesFrom: AllowMessagesFrom(rawValue: user.allowMessagesFrom ?? "all") ?? .all,
            allowGroupInvites: user.allowGroupInvites ?? true,
            spotifyAccount: user.spotifyAccount ?? "",
            instagramHandle: user.instagramHandle ?? "",
            tiktokHandle: user.tiktokHandle ?? ""
        )
    }

    func updateBody(
        comparedTo baseline: EditProfileDraft,
        requestAvatar: Bool,
        canChangeProfileType: Bool
    ) -> UpdateProfileBody {
        var body = UpdateProfileBody()

        let display = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseDisplay = baseline.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if display != baseDisplay { body.displayName = display }

        let bioText = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseBio = baseline.bio.trimmingCharacters(in: .whitespacesAndNewlines)
        if bioText != baseBio { body.bio = bioText }

        let location = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseLocation = baseline.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if location != baseLocation { body.locationName = location }

        if isPrivate != baseline.isPrivate { body.isPrivate = isPrivate }

        let songId = profileSongId.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseSongId = baseline.profileSongId.trimmingCharacters(in: .whitespacesAndNewlines)
        if songId != baseSongId { body.profileSongId = songId }

        if canChangeProfileType, profileType != baseline.profileType {
            body.profileType = profileType.rawValue
        }

        if allowMessagesFrom != baseline.allowMessagesFrom {
            body.allowMessagesFrom = allowMessagesFrom.rawValue
        }

        if allowGroupInvites != baseline.allowGroupInvites {
            body.allowGroupInvites = allowGroupInvites
        }

        let spotify = SpotifyAccountFormatting.normalizedAccount(from: spotifyAccount)
        let baseSpotify = SpotifyAccountFormatting.normalizedAccount(from: baseline.spotifyAccount)
        if spotify != baseSpotify { body.spotifyAccount = spotify }

        let instagram = instagramHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseInstagram = baseline.instagramHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        if instagram != baseInstagram { body.instagramHandle = instagram }

        let tiktok = tiktokHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseTiktok = baseline.tiktokHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        if tiktok != baseTiktok { body.tiktokHandle = tiktok }

        if requestAvatar { body.updateAvatar = true }

        return body
    }
}
