//
//  DiscoverSearchSupport.swift
//  Niche Music
//

import Kingfisher
import SwiftUI

extension GlobalSearchSuggestion {
    var trackReference: TrackDetailReference? {
        switch type {
        case "niche_track":
            return TrackDetailReference(id: entityId, source: "niche", sourceId: nil)
        case "track":
            let source = payload?.source ?? "apple_music"
            return TrackDetailReference(
                id: entityId,
                source: source,
                sourceId: payload?.sourceId ?? entityId
            )
        default:
            return nil
        }
    }

    var profileUsername: String? {
        if type == "profile" {
            return payload?.username ?? subtitle
        }
        return payload?.username
    }

    var artistSourceId: String? {
        if type == "artist" {
            return payload?.sourceId ?? entityId
        }
        return nil
    }

    var albumSourceId: String? {
        if type == "album" {
            return payload?.sourceId ?? entityId
        }
        return nil
    }

    var playlistId: String? {
        type == "playlist" ? entityId : nil
    }

    var badgeId: String? {
        type == "badge" ? entityId : nil
    }

    var sourceMark: DiscoverSearchSourceMark? {
        switch type {
        case "niche_track":
            return .niche
        case "track", "album", "artist":
            let source = payload?.source ?? "apple_music"
            if source == "apple_music" {
                return .appleMusic
            }
            if source == "niche" {
                return .niche
            }
            return nil
        default:
            return nil
        }
    }
}

enum DiscoverSearchSourceMark {
    case niche
    case appleMusic
}

struct DiscoverSearchSourceBadge: View {
    let mark: DiscoverSearchSourceMark

    var body: some View {
        Group {
            switch mark {
            case .niche:
                Image("favicon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            case .appleMusic:
                Image("appleMusicLogo")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: 18, height: 18)
        .foregroundStyle(.white.opacity(0.32))
        .opacity(mark == .appleMusic ? 0.55 : 0.42)
    }
}

struct DiscoverSearchField: View {
    @Binding var text: String
    let placeholder: String
    let isActive: Bool
    var onActivate: () -> Void
    var onSubmit: () -> Void = {}

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))

            if isActive {
                TextField(placeholder, text: $text)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .submitLabel(.search)
                    .onSubmit(onSubmit)
            } else {
                Text(placeholder)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            if !isActive {
                onActivate()
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                isFocused = true
            } else {
                isFocused = false
            }
        }
    }
}

struct DiscoverSearchSuggestionRow: View {
    let suggestion: GlobalSearchSuggestion
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                DiscoverSearchArtwork(urlString: suggestion.imageUrl, type: suggestion.type)

                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)

                    if let subtitle = suggestion.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if let sourceMark = suggestion.sourceMark {
                    DiscoverSearchSourceBadge(mark: sourceMark)
                }

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.28))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct DiscoverSearchResultRow: View {
    let title: String
    let subtitle: String?
    let imageUrl: String?
    var artworkType: String? = nil
    var sourceMark: DiscoverSearchSourceMark? = nil

    var body: some View {
        HStack(spacing: 12) {
            DiscoverSearchArtwork(urlString: imageUrl, type: artworkType)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if let sourceMark {
                DiscoverSearchSourceBadge(mark: sourceMark)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct DiscoverSearchArtwork: View {
    let urlString: String?
    let type: String?

    var body: some View {
        Group {
            if type == "profile" {
                artworkContent
                    .clipShape(Circle())
            } else {
                artworkContent
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .frame(width: 46, height: 46)
    }

    @ViewBuilder
    private var artworkContent: some View {
        if let urlString, let url = resolvedURL(urlString) {
            KFImage(url)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay {
                    Image(systemName: fallbackIcon)
                        .foregroundStyle(.white.opacity(0.28))
                }
        }
    }

    private var fallbackIcon: String {
        switch type {
        case "profile": return "person.fill"
        case "artist": return "music.mic"
        case "album", "playlist": return "square.stack"
        case "badge": return "rosette"
        default: return "music.note"
        }
    }

    private func resolvedURL(_ template: String) -> URL? {
        let resolved = template
            .replacingOccurrences(of: "{w}x{h}", with: "120x120")
            .replacingOccurrences(of: "{w}", with: "120")
            .replacingOccurrences(of: "{h}", with: "120")
        return URL(string: resolved)
    }
}

struct DiscoverSearchBadgeResultRow: View {
    let badge: GlobalSearchBadgeResult

    var body: some View {
        HStack(spacing: 12) {
            badgeArtwork
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 4) {
                Text(badge.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                Text("Badge")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var badgeArtwork: some View {
        if let color = Color.badgeHex(badge.colorHex ?? "ffffff") {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.85))
                .overlay {
                    Text(badge.displayTitle.prefix(1).uppercased())
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                }
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay {
                    Image(systemName: "rosette")
                        .foregroundStyle(.white.opacity(0.28))
                }
        }
    }
}

struct DiscoverSearchSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(0.48))
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DiscoverSearchSuggestionDestination: View {
    let suggestion: GlobalSearchSuggestion

    var body: some View {
        Group {
            if let reference = suggestion.trackReference, reference.canOpen {
                trackDetailDestination(reference)
            } else if let username = suggestion.profileUsername {
                OtherProfileView(username: username)
            } else if let sourceId = suggestion.artistSourceId {
                AppleArtistDetailView(sourceId: sourceId, ownerUsername: nil)
            } else if let sourceId = suggestion.albumSourceId {
                AppleAlbumDetailView(sourceId: sourceId)
            } else if let playlistId = suggestion.playlistId {
                PlaylistDetailView(playlistId: playlistId)
            } else if let badgeId = suggestion.badgeId {
                BadgeDetailView(badgeId: badgeId)
            } else {
                Text("Unable to open result")
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .toolbarVisibility(.hidden, for: .tabBar)
    }
}
