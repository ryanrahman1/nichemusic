//
//  CreatePostModels.swift
//  Niche Music
//

import Foundation

enum CreatePostType: String, CaseIterable, Identifiable, Codable {
    case image
    case video
    case pmo

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "image", "moment": self = .image
        case "video": self = .video
        case "pmo", "text", "track": self = .pmo
        default: self = .image
        }
    }

    var title: String {
        switch self {
        case .image: return "Image"
        case .video: return "Video"
        case .pmo: return "Put Me On"
        }
    }

    var icon: String {
        switch self {
        case .image: return "photo"
        case .video: return "video.fill"
        case .pmo: return "sparkles"
        }
    }

    var apiKind: PostKind {
        switch self {
        case .image: return .image
        case .video: return .video
        case .pmo: return .pmo
        }
    }

    var allowsMedia: Bool {
        self == .image || self == .video
    }

    var requiresNicheMusicOnly: Bool {
        self == .image || self == .video
    }

    var allowsAnyMusic: Bool {
        self == .pmo
    }
}

enum CreatePostCaptureMode: String, Codable {
    case photo
    case video
}

enum CreatePostMusicSource: String, Codable {
    case niche
    case catalog
}

struct CreatePostMusicSelection: Equatable, Codable {
    let source: CreatePostMusicSource
    let nicheTrackId: String?
    let catalogTrackId: String?
    let appleSourceId: String?
    let title: String
    let artistName: String
    let artworkUrl: String?

    static func niche(_ track: NicheTrackSearchResult) -> CreatePostMusicSelection {
        CreatePostMusicSelection(
            source: .niche,
            nicheTrackId: track.id,
            catalogTrackId: nil,
            appleSourceId: nil,
            title: track.name,
            artistName: track.primaryArtistName ?? track.owner?.displayName ?? track.owner?.username ?? "",
            artworkUrl: track.artworkUrl
        )
    }

    static func catalog(
        internalTrackId: String,
        appleSourceId: String,
        title: String,
        artistName: String,
        artworkUrl: String?
    ) -> CreatePostMusicSelection {
        CreatePostMusicSelection(
            source: .catalog,
            nicheTrackId: nil,
            catalogTrackId: internalTrackId,
            appleSourceId: appleSourceId,
            title: title,
            artistName: artistName,
            artworkUrl: artworkUrl
        )
    }
}

struct CreatePostLocalMedia: Equatable {
    enum Kind: String, Codable {
        case image
        case video
    }

    let kind: Kind
    let fileURL: URL
    let width: Int
    let height: Int
    let durationMs: Int?
}

struct PostDraftRecord: Identifiable, Codable, Equatable {
    let id: String
    var postId: String
    var postType: CreatePostType
    var captureMode: CreatePostCaptureMode
    var caption: String
    var visibility: PostVisibility
    var music: CreatePostMusicSelection?
    var mediaFileName: String?
    var mediaKind: CreatePostLocalMedia.Kind?
    var mediaWidth: Int?
    var mediaHeight: Int?
    var mediaDurationMs: Int?
    var updatedAt: Date

    var previewLabel: String {
        if !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return caption
        }
        if let music {
            return music.title
        }
        return postType.title
    }
}

struct PostMediaPresignBody: Encodable {
    let postId: String?
    let mediaKind: String
    let format: String
}

struct PostMediaPresignUpload: Decodable {
    let uploadUrl: String
    let objectKey: String
    let publicUrl: String
    let contentType: String
    let maxBytes: Int
}

struct PostMediaPresignResponse: Decodable {
    let postId: String
    let upload: PostMediaPresignUpload
}

struct CreatePostMediaInput: Encodable {
    let kind: String
    let objectKey: String
    let width: Int
    let height: Int
    let durationMs: Int?

    enum CodingKeys: String, CodingKey {
        case kind
        case objectKey
        case width
        case height
        case durationMs = "duration_ms"
    }
}

struct CreatePostTemplateBody: Encodable {
    let name: String
    let data: CreatePostTemplateDataBody
}

struct CreatePostTemplateDataBody: Encodable {
    let prompt: String
    let allowTrackReplies: Bool

    enum CodingKeys: String, CodingKey {
        case prompt
        case allowTrackReplies = "allow_track_replies"
    }
}

struct CreatePostContentBody: Encodable {
    let version: Int
    let kind: String
    let caption: String
    let media: [CreatePostMediaInput]
    let template: CreatePostTemplateBody?
    let metadata: [String: String]
}

struct CreatePostBody: Encodable {
    let postId: String
    let kind: String
    let visibility: String
    let trackId: String?
    let nicheTrackId: String?
    let content: CreatePostContentBody
}

struct CreatePostResultResponse: Decodable {
    let post: CreatedPostStub
}

struct CreatedPostStub: Decodable {
    let id: String
}

enum CreatePostPublishStage: Equatable {
    case idle
    case preparing
    case uploadingMedia
    case creatingPost
    case finishing
    case completed(postId: String)
    case failed(String)
}

enum CreatePostStoreError: LocalizedError {
    case missingMedia
    case missingMusic
    case missingCaption
    case mediaTooLarge
    case uploadFailed
    case cancelled
    case invalidState

    var errorDescription: String? {
        switch self {
        case .missingMedia: return "Add a photo or video to continue."
        case .missingMusic: return "Add a track to continue."
        case .missingCaption: return "Write a caption to continue."
        case .mediaTooLarge: return "Media exceeds the upload size limit."
        case .uploadFailed: return "Upload failed. Try again."
        case .cancelled: return "Upload cancelled."
        case .invalidState: return "Something went wrong. Try again."
        }
    }
}

enum CreatePostID {
    static func makePostId(length: Int = 16) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }
}
