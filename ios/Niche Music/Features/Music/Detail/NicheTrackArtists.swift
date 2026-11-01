//
//  NicheTrackArtists.swift
//  Niche Music
//

import SwiftUI

extension NicheTrackCreditArtist {
    var resolvedDisplayName: String {
        displayName ?? username
    }
}

extension NicheTrackCreditArtist: Identifiable {}

struct TrackArtistSheetRow: Identifiable {
    let id: String
    let username: String
    let displayName: String
    let role: String
    let profileType: String?
}

extension NicheTrack {
    var sortedCredits: [NicheTrackCredit] {
        (credits ?? []).sorted { lhs, rhs in
            let lhsPrimary = lhs.isPrimary == true
            let rhsPrimary = rhs.isPrimary == true
            if lhsPrimary != rhsPrimary { return lhsPrimary && !rhsPrimary }

            let lhsName = lhs.artist?.resolvedDisplayName ?? ""
            let rhsName = rhs.artist?.resolvedDisplayName ?? ""
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }
    }

    var sortedFeaturedArtists: [NicheTrackCreditArtist] {
        var seen = Set<String>()
        return sortedCredits.compactMap { credit in
            guard let artist = credit.artist, seen.insert(artist.id).inserted else { return nil }
            return artist
        }
    }

    var displayArtistLine: String {
        let artists = sortedFeaturedArtists
        if artists.isEmpty {
            return owner.displayName ?? owner.username
        }
        return artists.map(\.resolvedDisplayName).joined(separator: ", ")
    }

    var artistSheetEntries: [TrackArtistSheetRow] {
        var rows: [TrackArtistSheetRow] = []

        for credit in sortedCredits {
            guard let artist = credit.artist else { continue }
            rows.append(
                TrackArtistSheetRow(
                    id: artist.id,
                    username: artist.username,
                    displayName: artist.resolvedDisplayName,
                    role: credit.isPrimary == true ? "Primary Artist" : "Artist",
                    profileType: artist.profileType
                )
            )
        }

        if !rows.contains(where: { $0.id == owner.id }) {
            rows.append(
                TrackArtistSheetRow(
                    id: owner.id,
                    username: owner.username,
                    displayName: owner.displayName ?? owner.username,
                    role: "Uploader",
                    profileType: owner.profileType
                )
            )
        }

        return rows
    }

    var shouldShowArtistSheet: Bool {
        artistSheetEntries.count > 1
    }

    var soleArtistUsername: String? {
        guard !shouldShowArtistSheet else { return nil }
        return artistSheetEntries.first?.username
    }
}

struct TrackFeaturedArtistLine: View {
    let track: NicheTrack
    var onOpenProfile: ((String) -> Void)? = nil
    var font: Font = .system(size: 16, weight: .regular)
    var foreground: Color = .white.opacity(0.6)
    var alignment: TextAlignment = .leading
    var lineLimit: Int = 1

    @State private var showArtistPicker = false
    @EnvironmentObject private var appNavigation: AppNavigationRouter

    var body: some View {
        Group {
            if track.shouldShowArtistSheet {
                Button {
                    showArtistPicker = true
                } label: {
                    labelText
                }
                .buttonStyle(.plain)
            } else if let username = track.soleArtistUsername {
                profileButton(username: username) {
                    labelText
                }
            } else {
                profileButton(username: track.owner.username) {
                    labelText
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
        .sheet(isPresented: $showArtistPicker) {
            TrackArtistPickerSheet(track: track) { username in
                showArtistPicker = false
                openProfile(username)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(.clear)
        }
    }

    @ViewBuilder
    private func profileButton<Label: View>(
        username: String,
        @ViewBuilder label: @escaping () -> Label
    ) -> some View {
        if let onOpenProfile {
            Button {
                openProfile(username)
            } label: {
                label()
            }
            .buttonStyle(.plain)
        } else {
            ProfileUsernameLink(username: username) {
                label()
            }
        }
    }

    private func openProfile(_ username: String) {
        if let onOpenProfile {
            onOpenProfile(username)
            return
        }

        appNavigation.profileRoute = ProfileNavigationRoute(username: username)
    }

    private var labelText: some View {
        MarqueeText(
            text: track.displayArtistLine,
            font: font,
            foreground: foreground,
            textAlignment: alignment
        )
        .frame(minWidth: 0, maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }
}

struct TrackArtistPickerSheet: View {
    let track: NicheTrack
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Artists")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 14)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(track.artistSheetEntries.enumerated()), id: \.element.id) { index, entry in
                        Button {
                            onSelect(entry.username)
                        } label: {
                            artistRowLabel(entry)
                        }
                        .buttonStyle(.plain)

                        if index < track.artistSheetEntries.count - 1 {
                            Divider()
                                .overlay(.primary.opacity(0.08))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private func artistRowLabel(_ entry: TrackArtistSheetRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("\(entry.role) · @\(entry.username)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
