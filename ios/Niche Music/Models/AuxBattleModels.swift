//
//  AuxBattleModels.swift
//  Niche Music
//

import Foundation

enum AuxRoomStatus: String, Decodable, Equatable {
    case lobby
    case submitting
    case bracket
    case matchupPlaying = "matchup_playing"
    case voting
    case finished
    case cancelled
    case error
}

enum AuxSongSource: String, Codable, CaseIterable, Equatable {
    case niche
    case apple
    case any

    var label: String {
        switch self {
        case .niche: return "Niche Music"
        case .apple: return "Apple Music"
        case .any: return "All sources"
        }
    }
}

enum AuxMatchupStatus: String, Decodable, Equatable {
    case pending
    case playingA = "playing_a"
    case playingB = "playing_b"
    case voting
    case finished
}

enum AuxSubmissionSource: String, Codable, Equatable {
    case niche
    case apple
}

struct AuxBattleProfile: Decodable, Equatable {
    let id: String
    let username: String?
    let displayName: String?
    let avatarUrl: String?
    let isVerified: Bool?

    var displayLabel: String {
        displayName ?? username ?? id.prefix(8).description
    }
}

struct AuxBattleRoom: Decodable, Equatable {
    let id: String
    let code: String
    let hostId: String
    let prompt: String?
    let maxPlayers: Int
    let snippetLengthSeconds: Int
    let songSource: AuxSongSource
    let status: AuxRoomStatus
    let currentMatchupId: String?
    let createdAt: String?
    let startedAt: String?
    let finishedAt: String?
}

struct AuxBattleSubmission: Decodable, Equatable, Identifiable {
    let id: String
    let userId: String
    let source: AuxSubmissionSource?
    let trackId: String?
    let nicheTrackId: String?
    let trackName: String?
    let artistName: String?
    let artworkUrl: String?
    let musicUrl: String?
    let snippetStartMs: Int?
    let snippetDurationMs: Int?
    let eliminatedAt: String?
    let createdAt: String?
    let profile: AuxBattleProfile?
}

struct AuxLockedSubmission: Decodable, Equatable {
    let userId: String
    let lockedIn: Bool?
}

struct AuxBattlePlayer: Decodable, Equatable, Identifiable {
    let userId: String
    let isHost: Bool
    let joinedAt: String?
    let profile: AuxBattleProfile?
    let hasSubmitted: Bool
    let submission: AuxSubmissionPayload?

    var id: String { userId }
}

enum AuxSubmissionPayload: Decodable, Equatable {
    case locked(AuxLockedSubmission)
    case full(AuxBattleSubmission)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let locked = try? container.decode(AuxLockedSubmission.self), locked.lockedIn == true {
            self = .locked(locked)
            return
        }
        self = .full(try container.decode(AuxBattleSubmission.self))
    }

    var isLockedOnly: Bool {
        if case .locked = self { return true }
        return false
    }
}

struct AuxBattleVoteCount: Decodable, Equatable {
    let a: Int
    let b: Int
}

struct AuxBattleVoter: Decodable, Equatable {
    let userId: String
    let submissionId: String
    let profile: AuxBattleProfile?
}

struct AuxBattleMatchup: Decodable, Equatable, Identifiable {
    let id: String
    let roundNumber: Int
    let matchupNumber: Int?
    let status: AuxMatchupStatus
    let submissionA: AuxBattleSubmission?
    let submissionB: AuxBattleSubmission?
    let winnerSubmissionId: String?
    let nextMatchupId: String?
    let nextSlot: String?
    let playAStartedAt: String?
    let playBStartedAt: String?
    let votingStartedAt: String?
    let voteCounts: AuxBattleVoteCount?
    let voters: [AuxBattleVoter]?
    let myVote: String?
    let finishedAt: String?
}

struct AuxBattleBracket: Decodable, Equatable {
    let matchups: [AuxBattleMatchup]
}

struct AuxBattlePlayAgain: Decodable, Equatable {
    let userIds: [String]?
    let myPlayAgain: Bool?
    let count: Int?
}

struct AuxBattleRematch: Decodable, Equatable {
    let roomId: String
    let code: String
}

struct AuxBattleMeta: Decodable, Equatable {
    let allSubmitted: Bool?
    let allVoted: Bool?
    let playerCount: Int?
}

struct AuxRoomState: Decodable, Equatable {
    let room: AuxBattleRoom
    let host: AuxBattleProfile?
    let players: [AuxBattlePlayer]
    let submissions: [AuxBattleSubmission]?
    let bracket: AuxBattleBracket?
    let currentMatchup: AuxBattleMatchup?
    let playAgain: AuxBattlePlayAgain?
    let rematch: AuxBattleRematch?
    let meta: AuxBattleMeta?
}

struct AuxCreateRoomBody: Encodable {
    let prompt: String
    let maxPlayers: Int
    let snippetLengthSeconds: Int
    let songSource: AuxSongSource
}

struct AuxJoinRoomBody: Encodable {
    let code: String
}

struct AuxUpdateSettingsBody: Encodable {
    let prompt: String?
    let maxPlayers: Int?
    let snippetLengthSeconds: Int?
    let songSource: AuxSongSource?
}

struct AuxSubmitSongBody: Encodable {
    let source: AuxSubmissionSource
    let nicheTrackId: String?
    let trackId: String?
    let snippetStartMs: Int
}

struct AuxVoteBody: Encodable {
    let submissionId: String
}

struct AuxLeaveResponse: Decodable {
    let left: Bool
}

struct AuxRematchCreateResponse: Decodable {
    let room: AuxRoomState
    let alreadyCreated: Bool?
}

enum AuxSongPickSource: Equatable {
    case niche(NicheTrackSearchResult)
    case apple(trackId: String, appleSourceId: String, name: String, artistName: String, artworkUrl: String?, previewUrl: String?, durationMs: Int?)

    var name: String {
        switch self {
        case .niche(let track): return track.name
        case .apple(_, _, let name, _, _, _, _): return name
        }
    }

    var artistName: String {
        switch self {
        case .niche(let track): return track.primaryArtistName ?? "Niche"
        case .apple(_, _, _, let artist, _, _, _): return artist
        }
    }

    var artworkUrl: String? {
        switch self {
        case .niche(let track): return track.artworkUrl
        case .apple(_, _, _, _, let artwork, _, _): return artwork
        }
    }

    var musicURL: URL? {
        switch self {
        case .niche(let track):
            return track.musicUrl.flatMap(URL.init(string:))
        case .apple(_, _, _, _, _, let preview, _):
            return preview.flatMap(URL.init(string:))
        }
    }

    var durationMs: Int {
        switch self {
        case .niche(let track): return track.durationMs ?? 180_000
        case .apple(_, _, _, _, _, _, let duration): return duration ?? 30_000
        }
    }
}

enum AuxGamePhase: Equatable {
    case home
    case lobby
    case submitting
    case bracket
    case matchup
    case voting
    case finished
}

enum AuxMatchupSide {
    case a
    case b
}

struct AuxSongDisplay: Equatable {
    let submissionId: String?
    let title: String
    let artist: String
    let artworkUrl: String?
    let isHidden: Bool

    static let hidden = AuxSongDisplay(
        submissionId: nil,
        title: "???",
        artist: "",
        artworkUrl: nil,
        isHidden: true
    )
}

extension AuxBattleMatchup {
    /// Song details stay hidden until that side plays; submitter identity stays hidden until the matchup finishes.
    func displayForSide(_ side: AuxMatchupSide) -> AuxSongDisplay {
        let submission = side == .a ? submissionA : submissionB

        let revealSong: Bool = switch status {
        case .pending:
            false
        case .playingA:
            side == .a
        case .playingB, .voting:
            true
        case .finished:
            true
        }

        guard revealSong, let submission else {
            return AuxSongDisplay(
                submissionId: submission?.id,
                title: "???",
                artist: "",
                artworkUrl: nil,
                isHidden: true
            )
        }

        return AuxSongDisplay(
            submissionId: submission.id,
            title: submission.trackName ?? "Unknown",
            artist: submission.artistName ?? "",
            artworkUrl: submission.artworkUrl,
            isHidden: false
        )
    }

    var bracketLabel: String {
        let left = submissionA != nil ? "???" : "—"
        let right = submissionB != nil ? "???" : "—"
        return "\(left) vs \(right)"
    }
}

extension AuxRoomState {
    func phase(currentUserId: String?) -> AuxGamePhase {
        switch room.status {
        case .lobby: return .lobby
        case .submitting: return .submitting
        case .finished: return .finished
        case .voting: return .voting
        case .cancelled, .error: return .home
        case .matchupPlaying, .bracket:
            if let matchup = resolvedCurrentMatchup {
                if matchup.status == .voting { return .voting }
                return .matchup
            }
            return .bracket
        }
    }

    var resolvedCurrentMatchup: AuxBattleMatchup? {
        if let currentMatchup { return currentMatchup }
        guard let id = room.currentMatchupId else { return nil }
        return bracket?.matchups.first { $0.id == id }
    }

    func nextPendingMatchup() -> AuxBattleMatchup? {
        bracket?.matchups.first {
            $0.status == .pending && $0.submissionA != nil && $0.submissionB != nil
        }
    }

    func isHost(userId: String?) -> Bool {
        guard let userId else { return false }
        return room.hostId == userId
    }

    func myPlayer(userId: String?) -> AuxBattlePlayer? {
        guard let userId else { return nil }
        return players.first { $0.userId == userId }
    }

    var winnerSubmission: AuxBattleSubmission? {
        guard let final = bracket?.matchups.first(where: { $0.nextMatchupId == nil && $0.winnerSubmissionId != nil }),
              let winnerId = final.winnerSubmissionId else { return nil }
        if final.submissionA?.id == winnerId { return final.submissionA }
        return final.submissionB
    }

    var winnerPlayer: AuxBattlePlayer? {
        guard let winner = winnerSubmission else { return nil }
        return players.first { $0.userId == winner.userId }
    }

    var winnerProfile: AuxBattleProfile? {
        winnerSubmission?.profile ?? winnerPlayer?.profile
    }
}

extension AuxBattleSubmission {
    var nicheTrackIdForLibrary: String? {
        nicheTrackId ?? (source == .niche ? trackId : nil)
    }
}
