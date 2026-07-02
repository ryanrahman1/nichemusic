//
//  MusicDetailSupport.swift
//  Niche Music
//

import AVFoundation
import Combine
import Kingfisher
import SwiftUI

enum MusicDetailFormatters {
    static func shortDate(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }

        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: iso) {
            return displayDate(date)
        }

        let fallback = DateFormatter()
        fallback.dateFormat = "yyyy-MM-dd"
        if let date = fallback.date(from: iso) {
            return displayDate(date)
        }

        return nil
    }

    static func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func count(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    static func duration(ms: Int) -> String {
        let total = max(0, ms / 1000)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    static func stripHTML(_ html: String?) -> String? {
        guard let html, !html.isEmpty else { return nil }
        return html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

func resolvedAppleArtworkURL(_ template: String?, size: Int) -> URL? {
    guard let template, !template.isEmpty else { return nil }

    let resolved = template
        .replacingOccurrences(of: "{w}x{h}", with: "\(size)x\(size)")
        .replacingOccurrences(of: "{w}", with: "\(size)")
        .replacingOccurrences(of: "{h}", with: "\(size)")

    return URL(string: resolved)
}

struct MusicDetailOptionsMenu: View {
    let shareURL: URL
    let shareTitle: String
    let reportTargetType: ReportTargetType
    let reportTargetId: String
    var reportedUserId: String?

    @State private var showReport = false

    var body: some View {
        Menu {
            Button {
                showReport = true
            } label: {
                Label("Report an Issue", systemImage: "exclamationmark.bubble")
            }

            ShareLink(item: shareURL, subject: Text(shareTitle)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .sheet(isPresented: $showReport) {
            NavigationStack {
                FeedbackFormView(
                    title: "Report an Issue",
                    placeholder: "Describe the issue with this page…",
                    buttonLabel: "Submit Report"
                ) { text in
                    try await ReportsService.submit(
                        targetType: reportTargetType,
                        targetId: reportTargetId,
                        message: text,
                        reportedUserId: reportedUserId,
                        content: ["source": "music_detail"]
                    )
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

struct MusicDetailLoadingState: View {
    var body: some View {
        VStack(spacing: 16) {
            NicheProgress()
            Text("Loading…")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundColor)
    }
}

struct MusicDetailErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Button(action: retry) {
                Text("Try Again")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(.white.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundColor)
    }
}

enum MusicDetailScrollSpace {
    static let name = "MUSIC_DETAIL_SCROLL"
}

private struct MusicDetailScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct MusicDetailScrollShell<Content: View>: View {
    let artworkURL: URL?
    @ViewBuilder var content: () -> Content

    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        ZStack {
            MusicDetailParallaxBackdrop(artworkURL: artworkURL, scrollOffset: scrollOffset)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: MusicDetailScrollOffsetKey.self,
                                value: geo.frame(in: .named(MusicDetailScrollSpace.name)).minY
                            )
                    }
                    .frame(height: 0)

                    content()
                }
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
            .coordinateSpace(name: MusicDetailScrollSpace.name)
            .scrollIndicators(.hidden)
            .onPreferenceChange(MusicDetailScrollOffsetKey.self) { scrollOffset = $0 }
        }
    }
}

struct MusicDetailParallaxBackdrop: View {
    let artworkURL: URL?
    var scrollOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let pullDown = max(scrollOffset, 0)
            let height = geo.size.height + pullDown

            Group {
                if let artworkURL {
                    KFImage(artworkURL)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width * 1.2, height: height * 1.2)
                        .blur(radius: 22)
                        .frame(width: geo.size.width, height: height)
                        .clipped()
                } else {
                    Theme.backgroundColor
                }
            }
            .frame(width: geo.size.width, height: height)
            .offset(y: pullDown > 0 ? -pullDown : 0)
        }
    }
}

struct MusicSocialStatButton: View {
    let icon: String
    let filledIcon: String?
    let value: Int
    let isActive: Bool
    let isDisabled: Bool
    let action: () -> Void

    init(
        icon: String,
        filledIcon: String? = nil,
        value: Int,
        isActive: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.filledIcon = filledIcon
        self.value = value
        self.isActive = isActive
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isActive ? (filledIcon ?? icon) : icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isActive ? Theme.accentColor : .white.opacity(0.88))

                Text(MusicDetailFormatters.count(value))
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.92))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.white.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }
}

struct MusicSocialShareButton<Label: View>: View {
    let url: URL
    let subject: Text
    @ViewBuilder var label: () -> Label

    var body: some View {
        ShareLink(item: url, subject: subject, label: label)
            .buttonStyle(.plain)
    }
}

struct MusicSocialSharePill: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))

            Text(MusicDetailFormatters.count(count))
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.white.opacity(0.07), in: Capsule())
    }
}

struct MusicPreviewPlayButton: View {
    let previewURL: URL?
    let isActive: Bool

    @StateObject private var preview = MusicPreviewPlayer()

    var body: some View {
        Button {
            guard let previewURL else { return }
            preview.toggle(url: previewURL, active: isActive)
        } label: {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.42))
                    .frame(width: 64, height: 64)

                Image(systemName: preview.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: preview.isPlaying ? 0 : 2)
            }
        }
        .buttonStyle(.plain)
        .opacity(previewURL == nil ? 0.35 : 1)
        .disabled(previewURL == nil)
        .onChange(of: isActive) { _, active in
            if !active {
                preview.stop()
            }
        }
        .onDisappear {
            preview.stop()
        }
    }
}

@MainActor
final class MusicPreviewPlayer: ObservableObject {
    @Published private(set) var isPlaying = false

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    func toggle(url: URL, active: Bool) {
        guard active else {
            stop()
            return
        }

        if isPlaying {
            stop()
            return
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        isPlaying = true
        player.play()

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stop()
            }
        }
    }

    func stop() {
        player?.pause()
        player = nil
        isPlaying = false

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }
}

struct AppleMusicOpenButton: View {
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 8) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 17, weight: .semibold))
                Text("Apple Music")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.92))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
            }
        }
    }
}

struct MusicDetailSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CatalogTrackRow: View {
    let track: CatalogTrack
    let showsArtist: Bool

    var body: some View {
        NavigationLink {
            AppleMusicDetailView(sourceId: track.sourceId)
                .toolbarVisibility(.hidden, for: .tabBar)
        } label: {
            HStack(spacing: 12) {
                artwork

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)

                    if showsArtist, let artistName = track.artistName, !artistName.isEmpty {
                        Text(artistName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if track.previewUrl != nil {
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.28))
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = resolvedAppleArtworkURL(track.artworkUrl, size: 120) {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.white.opacity(0.28))
                }
        }
    }
}

struct CatalogAlbumRow: View {
    let album: CatalogAlbum

    var body: some View {
        NavigationLink {
            AppleAlbumDetailView(sourceId: album.sourceId)
                .toolbarVisibility(.hidden, for: .tabBar)
        } label: {
            HStack(spacing: 12) {
                if let url = resolvedAppleArtworkURL(album.artworkUrl, size: 160) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .frame(width: 64, height: 64)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(album.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(2)

                    if let trackCount = album.trackCount {
                        Text("\(trackCount) tracks")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.42))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

struct NicheAlbumTrackRowView: View {
    let track: NicheAlbumTrackRow
    let owner: FullUser
    let isPlaying: Bool
    var canEdit: Bool = false
    let onPlay: () -> Void
    var onEdit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                HStack(spacing: 12) {
                    artwork

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if isPlaying {
                                PlayingBarsIndicator(color: Theme.accentColor, size: 15)
                            }

                            Text(track.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(isPlaying ? Theme.accentColor : .white.opacity(0.92))
                                .lineLimit(1)
                        }

                        Text(track.primaryArtistName(fallbackOwner: owner))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    if track.explicit {
                        Text("E")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.08), in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            NavigationLink {
                NicheTrackDetailView(trackId: track.id)
                    .toolbarVisibility(.hidden, for: .tabBar)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.28))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .contextMenu {
            if canEdit {
                NavigationLink {
                    EditPublishedTrackView(trackId: track.id)
                        .onAppear { onEdit?() }
                } label: {
                    Label("Edit track", systemImage: "pencil")
                }
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = URL(string: track.artworkUrl) {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.white.opacity(0.28))
                }
        }
    }
}

enum NicheAlbumPlayback {
    private struct PlayableEntry {
        let trackId: String
        let queued: QueuedTrack
    }

    private static func entries(
        from tracks: [NicheAlbumTrackRow],
        owner: FullUser,
        source: String
    ) -> [PlayableEntry] {
        tracks.compactMap { row in
            guard
                let nicheTrack = row.asNicheTrack(owner: owner),
                let url = URL(string: nicheTrack.musicUrl)
            else {
                return nil
            }

            return PlayableEntry(
                trackId: row.id,
                queued: QueuedTrack(track: nicheTrack, url: url, source: source)
            )
        }
    }

    static func play(
        tracks: [NicheAlbumTrackRow],
        startingAt track: NicheAlbumTrackRow,
        albumName: String,
        owner: FullUser,
        player: MusicPlayer
    ) {
        let source = PlaybackSource.album(albumName).label
        let playable = entries(from: tracks, owner: owner, source: source)
        guard let startIndex = playable.firstIndex(where: { $0.trackId == track.id }) else { return }
        player.playPlaylist(playable.map(\.queued), startIndex: startIndex, source: source)
    }
}

struct LiquidCapsuleGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
        }
    }
}

extension View {
    func liquidCapsuleGlass() -> some View {
        modifier(LiquidCapsuleGlass())
    }
}
