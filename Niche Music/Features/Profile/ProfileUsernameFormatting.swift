//
//  ProfileUsernameFormatting.swift
//  Niche Music
//

import Foundation

enum ProfileType: String, Decodable, Equatable, CaseIterable, Hashable {
    case artist
    case user
    case producer
    case dj

    var formattedLabel: String {
        switch self {
        case .artist: "Artist"
        case .user: "User"
        case .producer: "Producer"
        case .dj: "DJ"
        }
    }

    static func fromStored(_ raw: String) -> ProfileType {
        ProfileType(rawValue: raw.lowercased()) ?? .user
    }

    static var signupOrder: [ProfileType] {
        [.user, .artist, .producer, .dj]
    }

    var signupSubtitle: String {
        switch self {
        case .user: "Listen, post, and make playlists"
        case .artist: "Share your own music"
        case .producer: "Create, produce, and collaborate"
        case .dj: "Curate tracks, mixes, and sets"
        }
    }

    static func formatted(from raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased() == ProfileType.user.rawValue { return nil }
        return ProfileType(rawValue: trimmed.lowercased())?.formattedLabel ?? trimmed.capitalized
    }
}

enum ProfileTypeCooldown {
    static let intervalDays = 14

    static func canUpdate(typeUpdatedAt: String, now: Date = Date()) -> Bool {
        guard let lastUpdated = parseTimestamp(typeUpdatedAt) else { return true }
        guard let eligibleDate = Calendar.current.date(
            byAdding: .day,
            value: intervalDays,
            to: lastUpdated
        ) else {
            return false
        }
        return now >= eligibleDate
    }

    static func nextEligibleDate(typeUpdatedAt: String) -> Date? {
        guard let lastUpdated = parseTimestamp(typeUpdatedAt) else { return nil }
        return Calendar.current.date(byAdding: .day, value: intervalDays, to: lastUpdated)
    }

    static func parseTimestamp(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }

        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }

        let postgres = DateFormatter()
        postgres.locale = Locale(identifier: "en_US_POSIX")
        postgres.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX"
        if let date = postgres.date(from: value) { return date }

        postgres.dateFormat = "yyyy-MM-dd HH:mm:ssXXXXX"
        return postgres.date(from: value)
    }
}

enum ProfileUsernameFormatting {
    static func formattedUserType(_ profileType: String?) -> String? {
        ProfileType.formatted(from: profileType)
    }

    static func line(username: String, profileType: String?) -> String {
        let handle = "@\(username)"
        guard let formatted = formattedUserType(profileType) else { return handle }
        return "\(handle) - \(formatted)"
    }
}

extension FullUser {
    var formattedUserType: String? {
        ProfileUsernameFormatting.formattedUserType(profileType)
    }

    var profileTypeEnum: ProfileType {
        ProfileType.fromStored(profileType ?? ProfileType.user.rawValue)
    }

    var isUserProfileType: Bool {
        profileTypeEnum == .user
    }

    var isArtistProfileType: Bool {
        !isUserProfileType
    }

    var usernameWithTypeLine: String {
        ProfileUsernameFormatting.line(username: username, profileType: profileType)
    }

    var canUpdateProfileType: Bool {
        ProfileTypeCooldown.canUpdate(typeUpdatedAt: typeUpdatedAt)
    }

    var nextProfileTypeChangeDate: Date? {
        ProfileTypeCooldown.nextEligibleDate(typeUpdatedAt: typeUpdatedAt)
    }
}
