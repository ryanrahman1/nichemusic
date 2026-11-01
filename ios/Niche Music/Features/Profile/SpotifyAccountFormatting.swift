//
//  SpotifyAccountFormatting.swift
//  Niche Music
//

import Foundation

enum SpotifyAccountFormatting {
    /// Returns a Spotify user id from a pasted profile URL/URI, or the trimmed input unchanged.
    static func normalizedAccount(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let extracted = extractUserId(from: trimmed) {
            return extracted
        }

        return trimmed
    }

    static func extractUserId(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let uriId = extractFromSpotifyURI(trimmed) {
            return uriId
        }

        guard let url = URL(string: trimmed), let host = url.host?.lowercased(),
              host.contains("spotify.com") else {
            return nil
        }

        let pathParts = url.path.split(separator: "/").map(String.init)
        guard let userIndex = pathParts.firstIndex(where: { $0.lowercased() == "user" }),
              userIndex + 1 < pathParts.count else {
            return nil
        }

        let rawId = pathParts[userIndex + 1]
        return sanitizeId(rawId)
    }

    private static func extractFromSpotifyURI(_ value: String) -> String? {
        let parts = value.split(separator: ":").map(String.init)
        guard parts.count >= 3, parts[1].lowercased() == "user" else { return nil }
        return sanitizeId(parts[2])
    }

    private static func sanitizeId(_ raw: String) -> String? {
        let id = raw.split(separator: "?").first.map(String.init) ?? raw
        let cleaned = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
