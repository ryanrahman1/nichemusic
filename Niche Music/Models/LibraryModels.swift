//
//  LibraryModels.swift
//  Niche Music
//

import Foundation

enum LibraryTab: String, CaseIterable, Identifiable {
    case yourLibrary = "Your Library"
    case appleMusic = "Apple Music"

    var id: String { rawValue }
}

enum LibrarySource: Hashable {
    case yourLibrary
    case niche
    case appleMusic

    var displayName: String {
        switch self {
        case .yourLibrary: return "Your Library"
        case .niche: return "Niche"
        case .appleMusic: return "Apple Music"
        }
    }

    func matches(_ source: String) -> Bool {
        switch self {
        case .yourLibrary: return true
        case .niche: return source != "apple_music"
        case .appleMusic: return source == "apple_music"
        }
    }
}

enum LibraryContentFilter: String, CaseIterable, Identifiable {
    case songs = "Songs"
    case albums = "Albums"
    case artists = "Artists"

    var id: String { rawValue }
}

enum LibraryBrowseKind: String, Identifiable {
    case saved = "Saved"
    case liked = "Liked"
    case trending = "Trending"

    var id: String { rawValue }
}

struct LibraryBrowseRoute: Identifiable, Hashable {
    let source: LibrarySource
    let kind: LibraryBrowseKind
    let filter: LibraryContentFilter

    var id: String {
        "\(displayKey)-\(kind.rawValue)-\(filter.rawValue)"
    }

    private var displayKey: String {
        switch source {
        case .yourLibrary: return "your_library"
        case .niche: return "niche"
        case .appleMusic: return "apple_music"
        }
    }
}

struct LibrarySearchRoute: Identifiable, Hashable {
    let source: LibrarySource

    var id: String {
        switch source {
        case .yourLibrary: return "your-library-search"
        case .niche: return "niche-search"
        case .appleMusic: return "apple-search"
        }
    }
}

struct TrendingSongsResponse: Decodable {
    let songs: [TrendingTrack]
}

struct TrendingAlbumsResponse: Decodable {
    let albums: [TrendingAlbum]
}

struct TrendingArtistsResponse: Decodable {
    let artists: [TrendingArtist]
}

struct TrendingTrack: Decodable, Identifiable, Equatable {
    let id: String
    let source: String
    let sourceId: String
    let name: String
    let artworkUrl: String?
    let artistId: String?
    let albumId: String?
    let previewUrl: String?
    let releaseDate: String?
    let artistName: String?

    func asCatalogTrack() -> CatalogTrack {
        CatalogTrack(
            id: id,
            source: source,
            sourceId: sourceId,
            name: name,
            artworkUrl: artworkUrl,
            artistId: artistId,
            albumId: albumId,
            previewUrl: previewUrl,
            releaseDate: releaseDate,
            likeCount: 0,
            saveCount: 0,
            shareCount: 0,
            viewer: nil,
            artistName: artistName
        )
    }
}

struct TrendingAlbum: Decodable, Identifiable, Equatable {
    let id: String
    let source: String
    let sourceId: String
    let name: String
    let artistId: String?
    let artworkUrl: String?
    let releaseDate: String?
    let trackCount: Int?

    func asCatalogAlbum() -> CatalogAlbum {
        CatalogAlbum(
            id: id,
            source: source,
            sourceId: sourceId,
            name: name,
            artistId: artistId,
            artworkUrl: artworkUrl,
            copyright: nil,
            editorialNote: nil,
            releaseDate: releaseDate,
            trackCount: trackCount,
            likeCount: 0,
            saveCount: 0,
            shareCount: 0,
            viewer: nil
        )
    }
}

struct TrendingArtist: Decodable, Identifiable, Equatable {
    let id: String
    let source: String
    let sourceId: String
    let name: String
    let imageUrl: String?
    let ownerId: String?

    func asCatalogArtist() -> CatalogArtist {
        CatalogArtist(
            id: id,
            source: source,
            sourceId: sourceId,
            name: name,
            imageUrl: imageUrl,
            ownerId: ownerId,
            fanCount: nil,
            shareCount: 0,
            hasFullDiscography: nil
        )
    }
}

struct TrendingLibraryCursor: Codable {
    let cursorScore: Double?
    let cursorCreatedAt: String?
    let cursorId: String?

    init?(rawValue: String?) {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(TrendingLibraryCursor.self, from: data) else {
            return nil
        }
        self = decoded
    }
}

struct TrendingPage<T> {
    let items: [T]
    let nextCursor: String?
    let hasMore: Bool
}
