//
//  MusicMatchFullscreenView.swift
//  Niche Music
//

import SwiftUI
import Kingfisher

struct MusicMatchFullscreenView: View {
    let match: MusicMatch
    let viewerAvatarURL: URL?

    @ObservedObject var store: MusicMatchesStore
    var onOpenInbox: (() -> Void)?
    var onOpenConversation: ((String, MusicMatchOtherUser) -> Void)?
    var onDismiss: (() -> Void)?

    @State private var alertMessage: String?

    private var canRespond: Bool {
        match.status == "pending" && !match.viewerHasResponded
    }

    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()

            Circle()
                .fill(Theme.accentColor.opacity(0.22))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: -120, y: -260)

            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: 140, y: 220)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.2),
                    Color.black.opacity(0.85),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                strengthBadge
                    .padding(.top, 56)

                Spacer(minLength: 24)

                avatarCluster
                    .padding(.bottom, 28)

                VStack(spacing: 14) {
                    Text(match.headline)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(match.subtitle)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal, 28)

                highlightSection
                    .padding(.top, 28)
                    .padding(.horizontal, 24)

                Spacer(minLength: 20)

                actionButtons
                    .padding(.horizontal, 24)
                    .padding(.bottom, 44)
            }
        }
        .interactiveDismissDisabled(true)
        .alert("Music Match", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                alertMessage = nil
                dismiss()
            }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var strengthBadge: some View {
        Text(strengthLabel)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.white.opacity(0.1), in: Capsule())
    }

    private var strengthLabel: String {
        switch match.strength.lowercased() {
        case "insane": return "Insane match"
        case "strong": return "Strong match"
        default: return "Good match"
        }
    }

    private var avatarCluster: some View {
        ZStack {
            matchAvatar(url: viewerAvatarURL, size: 108)
                .offset(x: -34, y: 8)

            matchAvatar(url: URL(string: match.otherUser.avatarUrl ?? ""), size: 124)
                .overlay(
                    RoundedRectangle(cornerRadius: 62, style: .continuous)
                        .stroke(Theme.accentColor.opacity(0.55), lineWidth: 2)
                )
                .offset(x: 38, y: -10)
        }
        .frame(height: 150)
    }

    @ViewBuilder
    private var highlightSection: some View {
        let tracks = Array(match.reasonJson.highlightTracks.prefix(5))
        let genres = Array((match.reasonJson.sharedGenreSamples ?? []).prefix(8))
        let mutuals = Array((match.reasonJson.mutualSamples ?? []).prefix(8))

        if !tracks.isEmpty || !genres.isEmpty || !mutuals.isEmpty {
            VStack(spacing: 16) {
                if !tracks.isEmpty {
                    horizontalRail {
                        ForEach(tracks) { track in
                            compactTrackCard(track)
                        }
                    }
                }

                if !genres.isEmpty {
                    horizontalRail {
                        ForEach(genres) { genre in
                            compactGenreCard(genre.name)
                        }
                    }
                }

                if !mutuals.isEmpty {
                    horizontalRail {
                        ForEach(mutuals) { mutual in
                            compactMutualCard(mutual)
                        }

                        if match.reasonJson.mutuals > mutuals.count {
                            compactMoreMutualsCard(count: match.reasonJson.mutuals - mutuals.count)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    private func horizontalRail<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                content()
            }
            .padding(.horizontal, 24)
        }
        .padding(.horizontal, -24)
    }

    private func compactTrackCard(_ track: MusicMatchTrackSample) -> some View {
        HStack(spacing: 10) {
            artwork(for: track.artworkUrl)
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let artistName = track.artistName, !artistName.isEmpty {
                    Text(artistName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: 190, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func compactGenreCard(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.88))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .frame(minWidth: 74, maxWidth: 118)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.white.opacity(0.075), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }
    }

    private func compactMutualCard(_ mutual: MusicMatchMutualSample) -> some View {
        VStack(spacing: 6) {
            matchAvatar(url: URL(string: mutual.avatarUrl ?? ""), size: 38)

            Text(mutual.username)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 58)
        }
    }

    private func compactMoreMutualsCard(count: Int) -> some View {
        VStack(spacing: 6) {
            Circle()
                .fill(.white.opacity(0.1))
                .frame(width: 38, height: 38)
                .overlay {
                    Text("+\(count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                }

            Text("more")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.52))
                .frame(width: 58)
        }
    }

    private func trackRow(_ track: MusicMatchTrackSample) -> some View {
        HStack(spacing: 12) {
            artwork(for: track.artworkUrl)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let artistName = track.artistName, !artistName.isEmpty {
                    Text(artistName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if canRespond {
                Button {
                    Task { await handlePrimaryAction() }
                } label: {
                    Group {
                        if store.isResponding {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(match.actions.primary)
                                .font(.system(size: 17, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Theme.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(store.isResponding)

                Button {
                    Task { await handleSecondaryAction() }
                } label: {
                    Text(match.actions.secondary)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(.white.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(store.isResponding)
            } else {
                Text(statusLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))

                Button {
                    dismiss()
                } label: {
                    Text("Close")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(.white.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dismiss() {
        onDismiss?()
        if store.pendingMatch?.id == match.id {
            store.clearPendingMatch()
        }
    }

    private var statusLabel: String {
        if match.declinedByOther {
            return "Sorry, \(match.otherUser.resolvedDisplayName) rejected your match"
        }
        switch match.status {
        case "accepted": return "You already connected on this match"
        case "declined": return "You passed on this match"
        case "expired": return "This match expired"
        default:
            if match.isWaitingForOther {
                return "Waiting for \(match.otherUser.resolvedDisplayName) to accept"
            }
            return "This match is no longer active"
        }
    }

    private func handlePrimaryAction() async {
        if match.declinedByOther {
            alertMessage = "Sorry, \(match.otherUser.resolvedDisplayName) rejected your match"
            return
        }

        let result = await store.acceptMatch(match)
        switch result {
        case .mutualAccept(let conversationId):
            onOpenInbox?()
            onOpenConversation?(conversationId, match.otherUser)
            dismiss()
        case .waitingForOther:
            alertMessage = "You accepted! Waiting for \(match.otherUser.resolvedDisplayName) to accept too."
        case .rejectedByOther:
            alertMessage = "Sorry, \(match.otherUser.resolvedDisplayName) rejected your match"
        case .alreadyInactive, .failed:
            dismiss()
        }
    }

    private func handleSecondaryAction() async {
        await store.declineMatch(match)
        dismiss()
    }

    @ViewBuilder
    private func matchAvatar(url: URL?, size: CGFloat) -> some View {
        if let url {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.34))
                        .foregroundStyle(.white.opacity(0.45))
                }
        }
    }

    @ViewBuilder
    private func artwork(for urlString: String?) -> some View {
        if let urlString, let url = URL(string: urlString) {
            KFImage(url)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.1))
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.white.opacity(0.35))
                }
        }
    }
}

#if DEBUG
#Preview("Music Match") {
    MusicMatchFullscreenView(
        match: .preview,
        viewerAvatarURL: URL(string: User.preview.avatarUrl),
        store: MusicMatchesStore()
    )
}
#endif
