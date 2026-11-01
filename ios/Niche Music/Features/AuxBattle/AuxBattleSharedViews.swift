//
//  AuxBattleSharedViews.swift
//  Niche Music
//

import SwiftUI
import Kingfisher

enum AuxBattleHaptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

struct AuxBattleBackground: View {
    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()

            Circle()
                .fill(Theme.accentColor.opacity(0.24))
                .frame(width: 340, height: 340)
                .blur(radius: 90)
                .offset(x: -130, y: -280)

            Circle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .offset(x: 150, y: 260)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.15),
                    Color.black.opacity(0.82),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

struct AuxPrimaryButton: View {
    let title: String
    var isLoading = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button {
            AuxBattleHaptics.impact(.medium)
            action()
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(disabled ? Color.white.opacity(0.12) : Theme.accentColor, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled || isLoading)
    }
}

struct AuxSecondaryButton: View {
    let title: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button {
            AuxBattleHaptics.impact(.light)
            action()
        } label: {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(.white.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct AuxSection<Content: View>: View {
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

struct AuxPlayerRow: View {
    let player: AuxBattlePlayer
    var showSubmissionStatus = false

    var body: some View {
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
                }

                if showSubmissionStatus {
                    Text(player.hasSubmitted ? "Locked in" : "Choosing…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(player.hasSubmitted ? Color(hex: 0x3DDC97) : Theme.textSecondaryColor)
                }
            }

            Spacer(minLength: 0)

            if showSubmissionStatus {
                Image(systemName: player.hasSubmitted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(player.hasSubmitted ? Color(hex: 0x3DDC97) : .white.opacity(0.22))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct AuxAvatarView: View {
    let profile: AuxBattleProfile?
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let urlString = profile?.avatarUrl, let url = URL(string: urlString) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    Text((profile?.displayLabel.first.map(String.init) ?? "?").uppercased())
                        .font(.system(size: size * 0.34, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct AuxSongCard: View {
    enum Style {
        case standard
        case featured
    }

    let display: AuxSongDisplay
    var style: Style = .standard
    var isActive = false
    var isWinner = false
    var isLoser = false
    var onTap: (() -> Void)?

    init(
        display: AuxSongDisplay,
        style: Style = .standard,
        isActive: Bool = false,
        isWinner: Bool = false,
        isLoser: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.display = display
        self.style = style
        self.isActive = isActive
        self.isWinner = isWinner
        self.isLoser = isLoser
        self.onTap = onTap
    }

    init(
        submission: AuxBattleSubmission?,
        style: Style = .standard,
        isActive: Bool = false,
        isWinner: Bool = false,
        isLoser: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        if let submission {
            self.display = AuxSongDisplay(
                submissionId: submission.id,
                title: submission.trackName ?? "—",
                artist: submission.artistName ?? "",
                artworkUrl: submission.artworkUrl,
                isHidden: false
            )
        } else {
            self.display = .hidden
        }
        self.style = style
        self.isActive = isActive
        self.isWinner = isWinner
        self.isLoser = isLoser
        self.onTap = onTap
    }

    private var artworkSize: CGFloat {
        style == .featured ? 168 : 72
    }

    private var minHeight: CGFloat {
        style == .featured ? 300 : 170
    }

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
    }

    private var cardContent: some View {
        VStack(spacing: style == .featured ? 16 : 10) {
            artwork

            Text(display.title)
                .font(.system(size: style == .featured ? 20 : 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if !display.artist.isEmpty {
                Text(display.artist)
                    .font(.system(size: style == .featured ? 15 : 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondaryColor)
                    .lineLimit(1)
            }
        }
        .padding(style == .featured ? 20 : 12)
        .frame(maxWidth: style == .featured ? 320 : .infinity, minHeight: minHeight)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(cardBorderColor, lineWidth: isActive || isWinner ? 1.5 : 0.5)
        }
        .opacity(isLoser ? 0.45 : 1)
    }

    private var cardCornerRadius: CGFloat {
        style == .featured ? 20 : 14
    }

    private var cardBackground: Color {
        style == .featured ? .white.opacity(0.1) : .white.opacity(0.06)
    }

    private var cardBorderColor: Color {
        if isWinner {
            return Color(hex: 0x3DDC97).opacity(0.75)
        }
        if isActive {
            return Theme.accentColor.opacity(0.85)
        }
        return .white.opacity(style == .featured ? 0.12 : 0.08)
    }

    @ViewBuilder
    private var artwork: some View {
        if display.isHidden {
            RoundedRectangle(cornerRadius: style == .featured ? 16 : 10, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(width: artworkSize, height: artworkSize)
                .overlay {
                    Image(systemName: "questionmark")
                        .font(.system(size: style == .featured ? 44 : 28, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
        } else if let urlString = display.artworkUrl,
           let url = URL(string: urlString.replacingOccurrences(of: "{w}x{h}", with: style == .featured ? "320x320" : "120x120")) {
            KFImage(url)
                .fade(duration: 0.15)
                .resizable()
                .scaledToFill()
                .frame(width: artworkSize, height: artworkSize)
                .clipShape(RoundedRectangle(cornerRadius: style == .featured ? 16 : 10, style: .continuous))
                .shadow(color: .black.opacity(style == .featured ? 0.35 : 0.2), radius: style == .featured ? 16 : 8, y: style == .featured ? 8 : 4)
        } else {
            RoundedRectangle(cornerRadius: style == .featured ? 16 : 10, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(width: artworkSize, height: artworkSize)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: style == .featured ? 36 : 24, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }
        }
    }
}

struct AuxSmallCodeActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button {
            AuxBattleHaptics.impact(.light)
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Theme.textSecondaryColor)
        }
        .buttonStyle(.plain)
    }
}

struct AuxStageTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.white)
    }
}

struct AuxPromptText: View {
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt:")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textSecondaryColor)

            Text(prompt)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AuxRoomCodeDisplay: View {
    let code: String
    var showCopy = false
    var showQR = false
    var onCopy: (() -> Void)?
    var onShowQR: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Text("Room code")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textSecondaryColor)

            Text(code)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .tracking(4)
                .foregroundStyle(.white)

            if showCopy || showQR {
                HStack(spacing: 20) {
                    if showCopy {
                        AuxSmallCodeActionButton(title: "Copy code", systemImage: "doc.on.doc") {
                            onCopy?()
                        }
                    }

                    if showQR {
                        AuxSmallCodeActionButton(title: "Show QR code", systemImage: "qrcode") {
                            onShowQR?()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct AuxPlaybackStatusView: View {
    let countdown: Int?
    let isPlaying: Bool

    var body: some View {
        if let countdown, countdown > 0 {
            Text("\(countdown)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: countdown)
        } else if isPlaying {
            VStack(spacing: 10) {
                AuxPlayingIndicator()
                Text("Now playing")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondaryColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

struct AuxPlayingIndicator: View {
    @State private var phase = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.accentColor)
                    .frame(width: 5, height: phase ? barHeight(for: index) : 10)
                    .animation(
                        .easeInOut(duration: 0.38)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.08),
                        value: phase
                    )
            }
        }
        .frame(height: 34)
        .onAppear { phase = true }
        .onDisappear { phase = false }
    }

    private func barHeight(for index: Int) -> CGFloat {
        switch index {
        case 0: return 18
        case 1: return 30
        case 2: return 22
        default: return 28
        }
    }
}

struct AuxCountdownOverlay: View {
    let value: Int?

    var body: some View {
        if let value, value > 0 {
            Text("\(value)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
    }
}

struct AuxToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.surfaceColor.opacity(0.95), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
