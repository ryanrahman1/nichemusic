//
//  FeedModels.swift
//  Niche Music
//
//  Created by Ryan Rahman on 6/1/26.
//

import Foundation

struct FeedResult: Decodable {
    let items: [FeedItem]
}

struct FeedItem: Decodable, Identifiable {
    let type: String
    var post: FeedPost
    var viewer: FeedViewer

    var id: String { post.id }
}

struct FeedViewer: Decodable {
    var isLiked: Bool
    var isReposted: Bool
}

struct FeedPost: Decodable, Identifiable {
    let id: String
    let ownerId: String
    let groupId: String?
    let kind: String
    let trackId: String?
    let nicheTrackId: String?
    let visibility: String

    var likeCount: Int
    var repostCount: Int
    var commentCount: Int

    let viewCount: Int
    let createdAt: String
    let updatedAt: String?

    let content: FeedPostContent

    let hasMedia: Bool
    let hasTrack: Bool
    let hasSound: Bool
    let shareCount: Int

    let owner: FeedOwner
    let group: FeedGroup?
    let track: FeedTrack?
    let nicheTrack: PostNicheTrack?
}

struct FeedPostContent: Decodable {
    let kind: String
    let media: [FeedMedia]?
    let track: FeedContentTrack?
    let nicheTrack: PostNicheTrack?
    let caption: String?
    let version: Int?
    let metadata: FeedContentMetadata?
    let template: FeedTemplate?
    let analytics: FeedAnalytics?
    let originalSound: FeedOriginalSound?
}

struct FeedMedia: Decodable, Identifiable {
    let url: String
    let kind: String
    let width: Int?
    let height: Int?
    let objectKey: String?
    let durationMs: Int?

    var id: String { url }
}

struct FeedContentTrack: Decodable {
    let id: String?
    let title: String?
    let name: String?
    let source: String?
    let albumId: String?
    let artistId: String?
    let sourceId: String?
    let artistName: String?
    let artworkUrl: String?
    let previewUrl: String?
    let releaseDate: String?
}

struct FeedContentMetadata: Decodable {
    let layout: String?
    let source: String?
}

struct FeedTemplate: Decodable {
    let name: String?
    let data: FeedTemplateData?
}

struct FeedTemplateData: Decodable {
    let prompt: String?
    let allowTrackReplies: Bool?
}

struct FeedAnalytics: Decodable {
    let hasMedia: Bool?
    let hasTrack: Bool?
    let mediaCount: Int?
    let hasOriginalSound: Bool?
}

struct FeedOriginalSound: Decodable {
    let kind: String?
    let source: String?
}

struct FeedOwner: Decodable {
    let id: String
    let username: String
    let avatarUrl: String?
    let profileType: String?
    let typeUpdatedAt: String?
}

struct FeedGroup: Decodable {
    let id: String?
    let name: String?
}

struct FeedTrack: Decodable, Identifiable {
    let id: String
    let name: String
    let artist: FeedArtist
    let source: String
    let sourceId: String?
    let artworkUrl: String?
    let previewUrl: String?
}

struct FeedArtist: Decodable {
    let id: String
    let name: String
}

enum FeedPreviewAudio {
    static let nicheMaxSeconds: TimeInterval = 30
    /// Rough upper bound for ~30s of MP3 at 192kbps when requesting a byte range.
    static let nicheRangeByteLength = 720_000

    static func nichePreviewCacheKey(for musicURL: String) -> String {
        "niche-preview:\(musicURL)"
    }

    static func momentCacheKey(for momentURL: String) -> String {
        "moment:\(momentURL)"
    }

    static func isNichePreviewCacheKey(_ key: String) -> Bool {
        key.hasPrefix("niche-preview:")
    }

    static func isMomentCacheKey(_ key: String) -> Bool {
        key.hasPrefix("moment:")
    }
}

enum FeedPlayerMediaKind {
    case uploadedVideo
    case moment
    case catalogPreview
    case nichePreview

    func cacheKey(for url: String) -> String {
        switch self {
        case .uploadedVideo:
            return url
        case .moment:
            return FeedPreviewAudio.momentCacheKey(for: url)
        case .catalogPreview:
            return url
        case .nichePreview:
            return FeedPreviewAudio.nichePreviewCacheKey(for: url)
        }
    }

    static func kind(for cacheKey: String) -> FeedPlayerMediaKind? {
        if FeedPreviewAudio.isMomentCacheKey(cacheKey) { return .moment }
        if FeedPreviewAudio.isNichePreviewCacheKey(cacheKey) { return .nichePreview }
        return nil
    }
}

struct FeedActivePostMedia {
    let previewCacheKey: String?
    let previewKind: FeedPlayerMediaKind?
    let uploadedVideoURL: String?
    let momentURL: String?
}

extension FeedPost {
    var isPMO: Bool {
        kind == "pmo" || content.template?.name == "pmo"
    }

    var resolvedNicheTrack: PostNicheTrack? {
        nicheTrack ?? content.nicheTrack
    }

    var displayTrackTitle: String? {
        if let name = track?.name, !name.isEmpty { return name }
        if let title = content.track?.title ?? content.track?.name, !title.isEmpty { return title }
        if let niche = resolvedNicheTrack { return niche.displayTitle }
        return nil
    }

    var previewAudioURL: String? {
        activePostMedia.previewCacheKey
    }

    var uploadedVideoURL: String? {
        content.media?.first(where: { $0.kind == "video" })?.url
    }

    /// Muted looping visual for PMO posts only.
    var momentVisualURL: String? {
        guard isPMO else { return nil }
        guard uploadedVideoURL == nil else { return nil }
        guard let momentUrl = resolvedNicheTrack?.momentUrl, !momentUrl.isEmpty else { return nil }
        return momentUrl
    }

    var activePostMedia: FeedActivePostMedia {
        var previewCacheKey: String?
        var previewKind: FeedPlayerMediaKind?

        if isPMO {
            if let preview = track?.previewUrl ?? content.track?.previewUrl {
                previewCacheKey = preview
                previewKind = .catalogPreview
            } else if let musicUrl = resolvedNicheTrack?.musicUrl, !musicUrl.isEmpty {
                previewCacheKey = FeedPreviewAudio.nichePreviewCacheKey(for: musicUrl)
                previewKind = .nichePreview
            }
        } else if kind == "image" || kind == "video",
                  let musicUrl = resolvedNicheTrack?.musicUrl,
                  !musicUrl.isEmpty {
            previewCacheKey = FeedPreviewAudio.nichePreviewCacheKey(for: musicUrl)
            previewKind = .nichePreview
        }

        return FeedActivePostMedia(
            previewCacheKey: previewCacheKey,
            previewKind: previewKind,
            uploadedVideoURL: uploadedVideoURL,
            momentURL: momentVisualURL
        )
    }

    /// Large track title overlay — PMO and legacy track posts only.
    var shouldShowProminentTrackTitle: Bool {
        isPMO || kind == "track"
    }

    /// Posts that show the 30s preview play/pause ring on the action rail.
    var showsPreviewPlaybackControl: Bool {
        guard previewAudioURL != nil else { return false }
        if isPMO { return true }
        if kind == "image" || kind == "video" {
            return activePostMedia.previewKind == .nichePreview
        }
        return false
    }

    /// Post image media first, then track artwork.
    var primaryDisplayImageURL: URL? {
        if let imageMedia = content.media?.first(where: { $0.kind == "image" }),
           let url = URL(string: imageMedia.url) {
            return url
        }

        return track?.resolvedArtworkURL ?? resolvedNicheTrack?.resolvedArtworkURL
    }

    var railArtworkURL: URL? {
        track?.resolvedArtworkURL ?? resolvedNicheTrack?.resolvedArtworkURL
    }
}

extension FeedTrack {
    var resolvedArtworkURL: URL? {
        guard let artworkUrl else { return nil }

        let resolved = artworkUrl
            .replacingOccurrences(of: "{w}", with: "1000")
            .replacingOccurrences(of: "{h}", with: "1000")

        return URL(string: resolved)
    }
}
