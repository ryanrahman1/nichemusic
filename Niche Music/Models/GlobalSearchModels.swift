//
//  GlobalSearchModels.swift
//  Niche Music
//

import Foundation

struct GlobalSearchSuggestionsResponse: Decodable {
    let query: String
    let suggestions: [GlobalSearchSuggestion]
}

struct GlobalSearchSuggestion: Decodable, Identifiable, Hashable {
    let type: String
    let entityId: String
    let title: String
    let subtitle: String?
    let imageUrl: String?
    let payload: GlobalSearchSuggestionPayload?
    let score: Double?

    var id: String { "\(type)-\(entityId)" }

    enum CodingKeys: String, CodingKey {
        case type
        case entityId = "id"
        case title
        case subtitle
        case imageUrl
        case payload
        case score
    }
}

struct GlobalSearchSuggestionPayload: Decodable, Hashable {
    let source: String?
    let sourceId: String?
    let username: String?
    let ownerId: String?
    let albumId: String?
    let artistId: String?
}

struct GlobalSearchResponse: Decodable {
    let query: String
    let results: GlobalSearchResults
}

struct GlobalSearchResults: Decodable {
    let nicheTracks: [GlobalSearchNicheTrackResult]
    let tracks: [GlobalSearchCatalogTrackResult]
    let albums: [GlobalSearchAlbumResult]
    let playlists: [GlobalSearchPlaylistResult]
    let profiles: [GlobalSearchProfileResult]
    let artists: [GlobalSearchArtistResult]
    let posts: [GlobalSearchPostResult]
    let badges: [GlobalSearchBadgeResult]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nicheTracks = try container.decodeIfPresent([GlobalSearchNicheTrackResult].self, forKey: .nicheTracks) ?? []
        tracks = try container.decodeIfPresent([GlobalSearchCatalogTrackResult].self, forKey: .tracks) ?? []
        albums = try container.decodeIfPresent([GlobalSearchAlbumResult].self, forKey: .albums) ?? []
        playlists = try container.decodeIfPresent([GlobalSearchPlaylistResult].self, forKey: .playlists) ?? []
        profiles = try container.decodeIfPresent([GlobalSearchProfileResult].self, forKey: .profiles) ?? []
        artists = try container.decodeIfPresent([GlobalSearchArtistResult].self, forKey: .artists) ?? []
        posts = try container.decodeIfPresent([GlobalSearchPostResult].self, forKey: .posts) ?? []
        badges = try container.decodeIfPresent([GlobalSearchBadgeResult].self, forKey: .badges) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case nicheTracks
        case tracks
        case albums
        case playlists
        case profiles
        case artists
        case posts
        case badges
    }

    var isEmpty: Bool {
        nicheTracks.isEmpty
            && tracks.isEmpty
            && albums.isEmpty
            && playlists.isEmpty
            && profiles.isEmpty
            && artists.isEmpty
            && posts.isEmpty
            && badges.isEmpty
    }
}

struct GlobalSearchNicheTrackResult: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let artworkUrl: String?
    let score: Double?
    let owner: GlobalSearchProfileResult?
    let artists: [GlobalSearchNicheTrackArtist]?

    var displayArtistName: String? {
        if let artists, !artists.isEmpty {
            let names = artists.compactMap { artist -> String? in
                let name = artist.displayName ?? artist.username
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if !names.isEmpty {
                return names.joined(separator: ", ")
            }
        }

        if let owner {
            let name = owner.displayName ?? owner.username
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return nil
    }
}

struct GlobalSearchNicheTrackArtist: Decodable, Hashable {
    let id: String
    let username: String
    let displayName: String?
    let isPrimary: Bool?
    let profileType: String?
    let typeUpdatedAt: String?
}

struct GlobalSearchCatalogTrackResult: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let source: String?
    let sourceId: String?
    let artworkUrl: String?
    let score: Double?
    let artist: GlobalSearchArtistRef?
}

struct GlobalSearchAlbumResult: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let source: String?
    let sourceId: String?
    let artworkUrl: String?
    let score: Double?
    let artist: GlobalSearchArtistRef?
}

struct GlobalSearchPlaylistResult: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let imageUrl: String?
    let score: Double?
    let owner: GlobalSearchProfileResult?
}

struct GlobalSearchProfileResult: Decodable, Identifiable, Hashable {
    let id: String
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let score: Double?
    let profileType: String?
    let typeUpdatedAt: String?
}

struct GlobalSearchArtistResult: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let source: String?
    let sourceId: String?
    let imageUrl: String?
    let score: Double?
}

struct GlobalSearchPostResult: Decodable, Identifiable, Hashable {
    let id: String
    let score: Double?
}

struct GlobalSearchBadgeResult: Decodable, Identifiable, Hashable {
    let id: String
    let text: String
    let colorHex: String?
    let score: Double?

    var displayTitle: String { text }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case name
        case colorHex
        case score
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        if let decodedText = try container.decodeIfPresent(String.self, forKey: .text) {
            text = decodedText
        } else {
            text = try container.decodeIfPresent(String.self, forKey: .name) ?? "Badge"
        }
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex)
        score = try container.decodeIfPresent(Double.self, forKey: .score)
    }
}

struct GlobalSearchArtistRef: Decodable, Hashable {
    let id: String?
    let name: String?
    let source: String?
    let sourceId: String?
    let imageUrl: String?
}
