//
//  PostCommentModels.swift
//  Niche Music
//

import Foundation

struct CommentMutationResponse: Decodable {
    let message: String?
    let commentId: String?
}

struct CreateTextCommentBody: Encodable {
    let kind: String
    let text: String
    let parentCommentId: String?
    let replyToCommentId: String?

    init(text: String, parentCommentId: String?, replyToCommentId: String?) {
        kind = "text"
        self.text = text
        self.parentCommentId = parentCommentId
        self.replyToCommentId = replyToCommentId
    }
}

struct CreateGifCommentBody: Encodable {
    let kind: String
    let text: String
    let gif: CreateCommentGifBody
    let parentCommentId: String?
    let replyToCommentId: String?

    init(
        text: String,
        gif: CreateCommentGifBody,
        parentCommentId: String?,
        replyToCommentId: String?
    ) {
        kind = "gif"
        self.text = text
        self.gif = gif
        self.parentCommentId = parentCommentId
        self.replyToCommentId = replyToCommentId
    }
}

struct CreateCommentGifBody: Encodable {
    let id: String
    let url: String
    let width: Int
    let height: Int
}

struct CreateTrackCommentBody: Encodable {
    let kind: String
    let trackId: String
    let text: String
    let parentCommentId: String?
    let replyToCommentId: String?

    init(
        trackId: String,
        text: String,
        parentCommentId: String?,
        replyToCommentId: String?
    ) {
        kind = "track"
        self.trackId = trackId
        self.text = text
        self.parentCommentId = parentCommentId
        self.replyToCommentId = replyToCommentId
    }
}

struct GiphyPickResult: Equatable {
    let id: String
    let url: String
    let width: Int
    let height: Int
}

struct AppleMusicSearchResponse: Decodable {
    let data: AppleMusicSearchData
}

struct AppleMusicSearchData: Decodable {
    let results: AppleMusicSearchResults?
}

struct AppleMusicSearchResults: Decodable {
    let songs: AppleMusicSearchSongs?
    let albums: AppleMusicSearchAlbums?
    let artists: AppleMusicSearchArtists?
}

struct AppleMusicSearchAlbums: Decodable {
    let data: [AppleMusicSearchAlbum]?
}

struct AppleMusicSearchAlbum: Decodable, Identifiable, Equatable {
    let id: String
    let attributes: AppleMusicSearchAlbumAttributes
}

struct AppleMusicSearchAlbumAttributes: Decodable, Equatable {
    let name: String
    let artistName: String?
    let artwork: AppleMusicArtwork?
}

extension AppleMusicSearchAlbum {
    var artistName: String { attributes.artistName ?? "" }
    var artworkURL: URL? {
        guard let template = attributes.artwork?.url else { return nil }
        return URL(string: template
            .replacingOccurrences(of: "{w}", with: "120")
            .replacingOccurrences(of: "{h}", with: "120"))
    }
}

struct AppleMusicSearchArtists: Decodable {
    let data: [AppleMusicSearchArtist]?
}

struct AppleMusicSearchArtist: Decodable, Identifiable, Equatable {
    let id: String
    let attributes: AppleMusicSearchArtistAttributes
}

struct AppleMusicSearchArtistAttributes: Decodable, Equatable {
    let name: String
    let artwork: AppleMusicArtwork?
}

extension AppleMusicSearchArtist {
    var artworkURL: URL? {
        guard let template = attributes.artwork?.url else { return nil }
        return URL(string: template
            .replacingOccurrences(of: "{w}", with: "120")
            .replacingOccurrences(of: "{h}", with: "120"))
    }
}

struct AppleMusicSearchSongs: Decodable {
    let data: [AppleMusicSearchSong]?
}

struct AppleMusicSearchSong: Decodable, Identifiable, Equatable {
    let id: String
    let attributes: AppleMusicSearchSongAttributes
}

struct AppleMusicSearchSongAttributes: Decodable, Equatable {
    let name: String
    let artistName: String
    let artwork: AppleMusicArtwork?
}

struct AppleMusicArtwork: Decodable, Equatable {
    let url: String
}

extension AppleMusicSearchSong {
    var title: String { attributes.name }
    var artistName: String { attributes.artistName }

    var artworkURL: URL? {
        guard let template = attributes.artwork?.url else { return nil }
        let resolved = template
            .replacingOccurrences(of: "{w}", with: "120")
            .replacingOccurrences(of: "{h}", with: "120")
        return URL(string: resolved)
    }
}

struct AppleSongIdLookupResponse: Decodable {
    let track: AppleSongIdLookupTrack
}

struct AppleSongIdLookupTrack: Decodable {
    let id: String
}
