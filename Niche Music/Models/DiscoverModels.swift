//
//  DiscoverModels.swift
//  Niche Music
//

import Foundation

struct DiscoverHomeResponse: Decodable {
    let generatedAt: String?
    let limitPerSection: Int?
    let sections: DiscoverSections
}

struct DiscoverSections: Decodable {
    let forYou: [DiscoverNicheTrack]
    let trendingNicheTracks: [DiscoverNicheTrack]
    let newNicheReleases: [DiscoverNicheTrack]
    let featuredPlaylists: [DiscoverPlaylist]
    let artistSpotlight: DiscoverEditorial?
    let popularProfiles: [DiscoverProfile]
    let recentPosts: [ProfilePost]
    let badgesCommunitiesChallenges: [DiscoverBadgeCommunityItem]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        forYou = try container.decodeIfPresent([DiscoverNicheTrack].self, forKey: .forYou) ?? []
        trendingNicheTracks = try container.decodeIfPresent([DiscoverNicheTrack].self, forKey: .trendingNicheTracks) ?? []
        newNicheReleases = try container.decodeIfPresent([DiscoverNicheTrack].self, forKey: .newNicheReleases) ?? []
        featuredPlaylists = try container.decodeIfPresent([DiscoverPlaylist].self, forKey: .featuredPlaylists) ?? []
        artistSpotlight = try container.decodeIfPresent(DiscoverEditorial.self, forKey: .artistSpotlight)
        popularProfiles = try container.decodeIfPresent([DiscoverProfile].self, forKey: .popularProfiles) ?? []
        recentPosts = try container.decodeIfPresent([ProfilePost].self, forKey: .recentPosts) ?? []
        badgesCommunitiesChallenges = try container.decodeIfPresent(
            [DiscoverBadgeCommunityItem].self,
            forKey: .badgesCommunitiesChallenges
        ) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case forYou
        case trendingNicheTracks
        case newNicheReleases
        case featuredPlaylists
        case artistSpotlight
        case popularProfiles
        case recentPosts
        case badgesCommunitiesChallenges
    }
}

struct DiscoverNicheTrack: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let artworkUrl: String?
    let musicUrl: String?
    let durationMs: Int?
    let explicit: Bool?
    let owner: DiscoverProfileRef?
    let artists: [DiscoverTrackArtist]?

    var displayArtistName: String? {
        if let artists, !artists.isEmpty {
            let names = artists.compactMap { artist -> String? in
                let value = artist.displayName ?? artist.username
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if !names.isEmpty {
                return names.joined(separator: ", ")
            }
        }

        if let owner {
            let value = owner.displayName ?? owner.username
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return nil
    }
}

struct DiscoverTrackArtist: Decodable, Hashable {
    let id: String
    let username: String
    let displayName: String?
    let isPrimary: Bool?
    let profileType: String?
    let typeUpdatedAt: String?
}

struct DiscoverPlaylist: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let imageUrl: String?
    let trackCount: Int?
    let owner: DiscoverProfileRef?

    var displaySubtitle: String {
        if let owner {
            return owner.displayName ?? owner.username
        }
        let count = trackCount ?? 0
        return count == 1 ? "1 song" : "\(count) songs"
    }
}

struct DiscoverProfile: Decodable, Identifiable, Hashable {
    let id: String
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let bio: String?
    let followersCount: Int?
    let profileType: String?
    let typeUpdatedAt: String?
}

struct DiscoverProfileRef: Decodable, Hashable {
    let id: String
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let profileType: String?
    let typeUpdatedAt: String?
}

struct DiscoverEditorial: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String?
    let link: String?
    let imageUrl: String?
}

struct DiscoverBadgeCommunityItem: Decodable, Identifiable, Hashable {
    let type: String
    let id: String
    let name: String
    let subtitle: String?
    let imageUrl: String?
    let colorHex: String?
    let slug: String?
    let memberCount: Int?
    let holderCount: Int?

    var displaySubtitle: String {
        if type == "badge" {
            let count = holderCount ?? 0
            return count == 1 ? "1 holder" : "\(count) holders"
        }
        if type == "community" {
            let count = memberCount ?? 0
            return count == 1 ? "1 member" : "\(count) members"
        }
        return subtitle ?? ""
    }
}
