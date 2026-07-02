//
//  PlayerTrackDetailsSection.swift
//  Niche Music
//

import SwiftUI

struct PlayerTrackDetailsSection: View {
    let track: NicheTrack
    var useAdaptiveColors = false
    var onOpenProfile: ((String) -> Void)? = nil

    private var sectionTitleColor: Color {
        useAdaptiveColors ? .secondary : .white.opacity(0.55)
    }

    private var labelColor: Color {
        useAdaptiveColors ? .secondary : .white.opacity(0.42)
    }

    private var valueColor: Color {
        useAdaptiveColors ? .primary : .white.opacity(0.88)
    }

    private var cardBackground: Color {
        useAdaptiveColors ? .primary.opacity(0.06) : .white.opacity(0.07)
    }

    private var dividerColor: Color {
        useAdaptiveColors ? .primary.opacity(0.08) : .white.opacity(0.08)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if hasMetadataContent {
                detailsCard
            }

            if hasCreditsContent {
                creditsCard
            }
        }
    }

    private var hasMetadataContent: Bool {
        !metadataRows.isEmpty
    }

    private var hasCreditsContent: Bool {
        true
    }

    private var detailsCard: some View {
        PlayerDetailsCard(title: "Details", titleColor: sectionTitleColor, cardBackground: cardBackground) {
            VStack(spacing: 0) {
                ForEach(Array(metadataRows.enumerated()), id: \.offset) { index, row in
                    PlayerDetailsRow(
                        label: row.label,
                        value: row.value,
                        labelColor: labelColor,
                        valueColor: valueColor
                    )

                    if index < metadataRows.count - 1 {
                        Divider()
                            .overlay(dividerColor)
                    }
                }
            }
        }
    }

    private var creditsCard: some View {
        PlayerDetailsCard(title: "Credits", titleColor: sectionTitleColor, cardBackground: cardBackground) {
            VStack(spacing: 0) {
                ForEach(Array(track.sortedCredits.enumerated()), id: \.offset) { _, credit in
                    creditRow(credit)

                    Divider()
                        .overlay(dividerColor)
                }

                uploaderRow
            }
        }
    }

    private var uploaderRow: some View {
        HStack(spacing: 10) {
            Text("Uploader")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(labelColor)
                .frame(width: 92, alignment: .leading)

            profileLink(username: track.owner.username) {
                Text(track.owner.displayName ?? track.owner.username)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
    }

    private func creditRow(_ credit: NicheTrackCredit) -> some View {
        HStack(spacing: 10) {
            Text(credit.isPrimary == true ? "Primary Artist" : "Artist")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(labelColor)
                .frame(width: 92, alignment: .leading)

            if let artist = credit.artist {
                profileLink(username: artist.username) {
                    Text(artist.displayName ?? artist.username)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                }
            } else {
                Text("Unknown Artist")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(valueColor)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
    }

    private var metadataRows: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []

        if let released = MusicDetailFormatters.shortDate(track.releaseDate) ?? nonEmpty(track.releaseDate) {
            rows.append(("Released", released))
        }

        rows.append(("Length", MusicDetailFormatters.duration(ms: track.durationMs)))

        if track.bpm > 0 {
            rows.append(("BPM", "\(track.bpm)"))
        }

        if track.popularity > 0 {
            rows.append(("Popularity", "\(track.popularity)"))
        }

        if let metadata = track.metadata {
            if let mood = nonEmpty(metadata.mood) {
                rows.append(("Mood", mood.capitalized))
            }
            if let energy = metadata.energy {
                rows.append(("Energy", formatScore(energy)))
            }
            if let danceability = metadata.danceability {
                rows.append(("Danceability", formatScore(danceability)))
            }
            if let valence = metadata.valence {
                rows.append(("Valence", formatScore(valence)))
            }
            if let intensity = metadata.intensity {
                rows.append(("Intensity", formatScore(intensity)))
            }
            if let language = nonEmpty(metadata.language) {
                rows.append(("Language", language.uppercased()))
            }
            if let topics = metadata.topics, !topics.isEmpty {
                rows.append(("Topics", topics.joined(separator: ", ")))
            }
            if let explicitScore = metadata.explicitScore {
                rows.append(("Explicit Score", formatScore(explicitScore)))
            }
            if let extra = metadata.extra {
                for key in extra.keys.sorted() {
                    if let value = nonEmpty(extra[key]) {
                        rows.append((formatMetadataKey(key), value))
                    }
                }
            }
        }

        return rows
    }

    @ViewBuilder
    private func profileLink<Label: View>(
        username: String,
        @ViewBuilder label: @escaping () -> Label
    ) -> some View {
        if let onOpenProfile {
            Button {
                onOpenProfile(username)
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

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func formatScore(_ value: Int) -> String {
        "\(value)%"
    }

    private func formatMetadataKey(_ key: String) -> String {
        key
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

struct PlayerTrackDetailsSheet: View {
    let track: NicheTrack
    var onOpenProfile: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Track Info")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 14)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.name)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.primary)

                        TrackFeaturedArtistLine(
                            track: track,
                            onOpenProfile: onOpenProfile,
                            font: .system(size: 15, weight: .medium),
                            foreground: .secondary
                        )
                    }

                    PlayerTrackDetailsSection(
                        track: track,
                        useAdaptiveColors: true,
                        onOpenProfile: onOpenProfile
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }
}

private struct PlayerDetailsCard<Content: View>: View {
    let title: String
    let titleColor: Color
    let cardBackground: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(titleColor)
                .textCase(.uppercase)
                .tracking(0.4)

            content()
                .padding(.horizontal, 14)
                .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct PlayerDetailsRow: View {
    let label: String
    let value: String
    let labelColor: Color
    let valueColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(labelColor)
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(valueColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 11)
    }
}
