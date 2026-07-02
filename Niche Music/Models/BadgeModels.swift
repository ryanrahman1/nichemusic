//
//  BadgeModels.swift
//  Niche Music
//

import Foundation

struct BadgeDetailResponse: Decodable {
    let badge: BadgeDetail
}

struct BadgeDetail: Decodable, Equatable {
    let id: String
    let text: String
    let colorHex: String
    let createdAt: String?
    let holderCount: Int
}

struct BadgeHoldersResponse: Decodable {
    let holders: [BadgeHolder]
}

struct BadgeHolder: Decodable, Identifiable, Equatable {
    let userId: String
    let badgeIndex: Int?
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let isVerified: Bool?
    let verificationType: String?
    let profileType: String?
    let typeUpdatedAt: String?

    var id: String { userId }

    var displayTitle: String {
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty {
            return name
        }
        return username
    }
}

extension ProfileBadge {
    var asBadgeDetail: BadgeDetail {
        BadgeDetail(
            id: id,
            text: text,
            colorHex: colorHex,
            createdAt: createdAt,
            holderCount: 0
        )
    }
}

extension GlobalSearchBadgeResult {
    var asBadgeDetail: BadgeDetail {
        BadgeDetail(
            id: id,
            text: displayTitle,
            colorHex: colorHex ?? "ffffff",
            createdAt: nil,
            holderCount: 0
        )
    }
}

extension DiscoverBadgeCommunityItem {
    var badgeDetailPreview: BadgeDetail? {
        guard type == "badge" else { return nil }
        return BadgeDetail(
            id: id,
            text: name,
            colorHex: colorHex ?? "ffffff",
            createdAt: nil,
            holderCount: holderCount ?? 0
        )
    }
}
