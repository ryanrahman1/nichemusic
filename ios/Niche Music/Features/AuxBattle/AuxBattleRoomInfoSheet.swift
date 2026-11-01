//
//  AuxBattleRoomInfoSheet.swift
//  Niche Music
//

import SwiftUI

struct AuxBattleRoomInfoSheet: View {
    @ObservedObject var store: AuxBattleStore
    let currentUserId: String?

    @Environment(\.dismiss) private var dismiss

    private var state: AuxRoomState? { store.roomState }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                if let state {
                    VStack(alignment: .leading, spacing: 24) {
                        connectionSection
                        roomSection(state)
                        gameSection(state)
                        playersSection(state)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                } else {
                    ContentUnavailableView {
                        Label("No room", systemImage: "gamecontroller")
                    } description: {
                        Text("This game is no longer active.")
                    }
                    .padding(.top, 40)
                }
            }
            .background(Theme.backgroundColor.ignoresSafeArea())
            .navigationTitle("Game Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var connectionSection: some View {
        AuxInfoSection(title: "Connection") {
            HStack(spacing: 10) {
                Circle()
                    .fill(store.wsConnected ? Color(hex: 0x3DDC97) : .red.opacity(0.85))
                    .frame(width: 10, height: 10)

                Text(store.wsConnected ? "Connected" : "Disconnected")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func roomSection(_ state: AuxRoomState) -> some View {
        AuxInfoSection(title: "Room") {
            VStack(spacing: 0) {
                AuxInfoRow(label: "Code", value: state.room.code, monospaced: true)
                AuxInfoDivider()
                if let createdAt = AuxBattleDateFormatting.displayString(from: state.room.createdAt) {
                    AuxInfoRow(label: "Created", value: createdAt)
                    AuxInfoDivider()
                }
                if let startedAt = AuxBattleDateFormatting.displayString(from: state.room.startedAt) {
                    AuxInfoRow(label: "Started", value: startedAt)
                    AuxInfoDivider()
                }
                if let host = state.host ?? state.players.first(where: { $0.isHost })?.profile {
                    AuxInfoRow(label: "Host", value: host.displayLabel)
                } else {
                    AuxInfoRow(label: "Host", value: state.room.hostId.prefix(8).description)
                }
            }
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func gameSection(_ state: AuxRoomState) -> some View {
        AuxInfoSection(title: "Game") {
            VStack(spacing: 0) {
                AuxInfoRow(label: "Status", value: state.room.status.label)
                AuxInfoDivider()
                if let prompt = state.room.prompt, !prompt.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Prompt")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textSecondaryColor)
                        Text(prompt)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    AuxInfoDivider()
                }
                AuxInfoRow(
                    label: "Players",
                    value: "\(state.meta?.playerCount ?? state.players.count)/\(state.room.maxPlayers)"
                )
                AuxInfoDivider()
                AuxInfoRow(label: "Snippet", value: "\(state.room.snippetLengthSeconds)s")
                AuxInfoDivider()
                AuxInfoRow(label: "Song source", value: state.room.songSource.label)
            }
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func playersSection(_ state: AuxRoomState) -> some View {
        AuxInfoSection(title: "Players · \(state.players.count)") {
            VStack(spacing: 8) {
                ForEach(state.players) { player in
                    HStack(spacing: 12) {
                        AuxAvatarView(profile: player.profile)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(player.profile?.displayLabel ?? player.userId.prefix(8).description)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)

                                if player.isHost {
                                    Text("Host")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Theme.textSecondaryColor)
                                }

                                if player.userId == currentUserId {
                                    Text("You")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.accentColor)
                                }
                            }

                            if let joinedAt = AuxBattleDateFormatting.displayString(from: player.joinedAt) {
                                Text("Joined \(joinedAt)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.textSecondaryColor)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }
}

private struct AuxInfoSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            content
        }
    }
}

private struct AuxInfoRow: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textSecondaryColor)
                .frame(width: 88, alignment: .leading)

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: monospaced ? .monospaced : .default))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct AuxInfoDivider: View {
    var body: some View {
        Divider()
            .overlay(.white.opacity(0.08))
            .padding(.leading, 14)
    }
}

private enum AuxBattleDateFormatting {
    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func displayString(from value: String?) -> String? {
        guard let value, let date = parse(value) else { return nil }
        return displayFormatter.string(from: date)
    }

    private static func parse(_ value: String) -> Date? {
        if let date = iso8601WithFractional.date(from: value) { return date }
        return iso8601Standard.date(from: value)
    }
}

private extension AuxRoomStatus {
    var label: String {
        switch self {
        case .lobby: return "Lobby"
        case .submitting: return "Submitting songs"
        case .bracket: return "Bracket"
        case .matchupPlaying: return "Matchup"
        case .voting: return "Voting"
        case .finished: return "Finished"
        case .cancelled: return "Cancelled"
        case .error: return "Error"
        }
    }
}
