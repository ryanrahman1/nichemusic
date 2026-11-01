//
//  NicheURLParser.swift
//  Niche Music
//

import Foundation

enum NicheURLParser {
    private static let shareHosts: Set<String> = [
        "share.nichemusic.app",
        "www.share.nichemusic.app",
    ]

    private static let openHosts: Set<String> = [
        "open.nichemusic.app",
        "www.open.nichemusic.app",
    ]

    static func parse(_ raw: String) -> DeepLinkDestination? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("/") {
            return parsePathComponents(trimmed.split(separator: "/").map(String.init))
        }

        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else {
            return nil
        }

        if url.scheme?.lowercased() == "nichemusic" {
            return parseCustomScheme(url: url)
        }

        guard url.scheme?.lowercased() == "https" || url.scheme?.lowercased() == "http" else {
            return nil
        }

        if shareHosts.contains(host) || openHosts.contains(host) {
            let parts = url.path.split(separator: "/").map(String.init)
            return parsePathComponents(parts)
        }

        return nil
    }

    static func parse(_ url: URL) -> DeepLinkDestination? {
        parse(url.absoluteString)
    }

    private static func parseCustomScheme(url: URL) -> DeepLinkDestination? {
        var parts: [String] = []
        if let host = url.host, !host.isEmpty {
            parts.append(host)
        }
        parts.append(contentsOf: url.path.split(separator: "/").map(String.init))
        return parsePathComponents(parts)
    }

    private static func parsePathComponents(_ parts: [String]) -> DeepLinkDestination? {
        guard let head = parts.first?.lowercased(), parts.count >= 2 else { return nil }
        let rawId = parts[1]
        guard !rawId.isEmpty else { return nil }
        let id = rawId.removingPercentEncoding ?? rawId

        switch head {
        case "post", "posts":
            return .post(id: id)

        case "user", "users":
            return .profile(username: id)

        case "profile":
            guard parts.count >= 3 else { return nil }
            let sub = parts[1].lowercased()
            let profileId = parts[2].removingPercentEncoding ?? parts[2]
            if sub == "user" {
                return .profile(username: profileId)
            }
            return nil

        case "track", "tracks":
            return .shareTrack(id: id)

        case "artist", "artists":
            return .shareArtist(id: id)

        case "album", "albums":
            return .nicheAlbum(id: id)

        case "playlist", "playlists":
            return .playlist(id: id)

        case "inbox":
            return .conversation(id: id)

        case "music":
            return parseMusicPath(Array(parts.dropFirst()))

        default:
            return nil
        }
    }

    private static func parseMusicPath(_ parts: [String]) -> DeepLinkDestination? {
        guard parts.count >= 3 else { return nil }
        let provider = parts[0].lowercased()
        let kind = parts[1].lowercased()
        let rawId = parts[2]
        guard provider == "apple", !rawId.isEmpty else { return nil }
        let sourceId = rawId.removingPercentEncoding ?? rawId

        switch kind {
        case "song", "songs":
            return .track(TrackDetailReference(id: nil, source: "apple_music", sourceId: sourceId))
        case "artist", "artists":
            return .appleArtist(sourceId: sourceId)
        case "album", "albums":
            return .appleAlbum(sourceId: sourceId)
        default:
            return nil
        }
    }
}
