//
//  MusicMatchModels.swift
//  Niche Music
//

import Foundation

struct MusicMatchCheckResponse: Decodable {
    let match: MusicMatch?
}

struct MusicMatch: Decodable, Identifiable, Equatable {
    let id: String
    let strength: String
    let headline: String
    let subtitle: String
    let actions: MusicMatchActions
    let otherUser: MusicMatchOtherUser
    let reasonJson: MusicMatchReason
    let expiresAt: String
    let status: String
    let viewerHasResponded: Bool
    let otherHasResponded: Bool
    let declinedByUserId: String?

    var declinedByOther: Bool {
        guard status == "declined" else { return false }
        if let declinedByUserId {
            return declinedByUserId == otherUser.id
        }
        return otherHasResponded && !viewerHasResponded
    }

    var declinedByViewer: Bool {
        guard status == "declined" else { return false }
        if let declinedByUserId {
            return declinedByUserId != otherUser.id
        }
        return viewerHasResponded && !otherHasResponded
    }

    var isWaitingForOther: Bool {
        status == "pending" && viewerHasResponded && !otherHasResponded
    }
}

struct MusicMatchActions: Decodable, Equatable {
    let primary: String
    let secondary: String
}

struct MusicMatchOtherUser: Decodable, Equatable {
    let id: String
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let isVerified: Bool
    let verificationType: String?
    let profileType: String?
    let typeUpdatedAt: String?

    var resolvedDisplayName: String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? username : trimmed
    }
}

struct MusicMatchReason: Decodable, Equatable {
    let sharedAppleTracks: Int
    let sharedNicheTracks: Int
    let sharedNichePlays: Int
    let sharedFeedEvents: Int
    let sharedGenres: Int
    let mutuals: Int
    let topReasons: [String]
    let sharedAppleTrackSamples: [MusicMatchTrackSample]?
    let sharedNicheTrackSamples: [MusicMatchTrackSample]?
    let sharedNichePlayTrackSamples: [MusicMatchTrackSample]?
    let sharedFeedTrackSamples: [MusicMatchTrackSample]?
    let sharedGenreSamples: [MusicMatchGenreSample]?
    let mutualSamples: [MusicMatchMutualSample]?

    var highlightTracks: [MusicMatchTrackSample] {
        if let samples = sharedNichePlayTrackSamples, !samples.isEmpty { return samples }
        if let samples = sharedAppleTrackSamples, !samples.isEmpty { return samples }
        if let samples = sharedNicheTrackSamples, !samples.isEmpty { return samples }
        if let samples = sharedFeedTrackSamples, !samples.isEmpty { return samples }
        return []
    }
}

struct MusicMatchTrackSample: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let artworkUrl: String?
    let source: String?
    let artistName: String?
}

struct MusicMatchGenreSample: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let slug: String
}

struct MusicMatchMutualSample: Decodable, Equatable, Identifiable {
    let id: String
    let username: String
    let displayName: String?
    let avatarUrl: String?
}

struct MusicMatchRespondBody: Encodable {
    let action: String
}

struct MusicMatchRespondResponse: Decodable {
    let success: Bool?
    let accepted: Bool?
    let conversation: MusicMatchConversation?
}

struct MusicMatchConversation: Decodable, Equatable {
    let id: String
}

#if DEBUG
extension MusicMatch {
    static let preview = MusicMatch(
        id: "preview-match",
        strength: "strong",
        headline: "Your music taste matched",
        subtitle: "You and srihith both listened to \"don't tell me it's over\" and have 5 mutuals.",
        actions: MusicMatchActions(primary: "Say hi", secondary: "Maybe later"),
        otherUser: MusicMatchOtherUser(
            id: "other-user",
            username: "srihith",
            displayName: "srihith",
            avatarUrl: "https://cdn.nichemusic.app/avatars/cqXcxocvtYdEFnoDppneHg/avatar-cAZ-xSAdwUSalGao.jpg",
            isVerified: false,
            verificationType: nil,
            profileType: "artist",
            typeUpdatedAt: "2026-03-14T12:34:27.652062+00:00"
        ),
        reasonJson: MusicMatchReason(
            sharedAppleTracks: 1,
            sharedNicheTracks: 0,
            sharedNichePlays: 1,
            sharedFeedEvents: 0,
            sharedGenres: 2,
            mutuals: 5,
            topReasons: [
                "You both listened to \"don't tell me it's over\"",
                "You have 5 mutuals"
            ],
            sharedAppleTrackSamples: nil,
            sharedNicheTrackSamples: nil,
            sharedNichePlayTrackSamples: [
                MusicMatchTrackSample(
                    id: "track-1",
                    name: "don't tell me it's over",
                    artworkUrl: nil,
                    source: "niche",
                    artistName: "Artist"
                )
            ],
            sharedFeedTrackSamples: nil,
            sharedGenreSamples: [
                MusicMatchGenreSample(id: "g1", name: "Indie", slug: "indie")
            ],
            mutualSamples: nil
        ),
        expiresAt: "2026-06-10T13:47:10.581736+00:00",
        status: "pending",
        viewerHasResponded: false,
        otherHasResponded: false,
        declinedByUserId: nil
    )
}
#endif
