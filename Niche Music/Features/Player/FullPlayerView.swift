//
//  FullPlayerView.swift
//  nichemusic
//
//  Created by Ryan Rahman on 5/9/26.
//

import SwiftUI
import Kingfisher
import AVFoundation

enum PlayerMode {
    case player
    case lyrics
    case comments
}

struct FullPlayerView: View {
    @EnvironmentObject var musicPlayer: MusicPlayer
    @EnvironmentObject var musicStore: MusicStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject private var appNavigation: AppNavigationRouter
    @Environment(\.dismiss) private var dismiss

    var onOpenTrackDetail: ((String) -> Void)? = nil
    var onOpenProfile: ((String) -> Void)? = nil

    @State private var isDragging = false
    @State private var dragStartX: CGFloat = 0
    @State private var dragStartProgress: Double = 0
    @State private var hasAppeared = false
    @State private var currentMode: PlayerMode = .player
    @Namespace private var modeNamespace
    @State private var showNoLyricsToast = false
    @State private var lyricsContributeURL: URL? = nil
    @State private var showLyricsIssueToast = false
    @State private var showQueue = false
    @State private var showTrackDetails = false
    private var hasReadyMoment: Bool {
        musicPlayer.momentReady &&
        musicPlayer.loadedMomentTrackId == musicPlayer.currentTrack?.id
    }

    private var displayTrack: NicheTrack? {
        guard let trackId = musicPlayer.currentTrack?.id else { return nil }
        return musicStore.track(id: trackId) ?? musicPlayer.currentTrack
    }

    private var currentTrackViewer: TrackViewer {
        guard let trackId = musicPlayer.currentTrack?.id else {
            return TrackViewer(isLiked: false, isSaved: false)
        }
        return musicStore.viewer(for: trackId)
    }

    init(
        hasLoadedMoment: Bool = false,
        onOpenTrackDetail: ((String) -> Void)? = nil,
        onOpenProfile: ((String) -> Void)? = nil
    ) {
        self.onOpenTrackDetail = onOpenTrackDetail
        self.onOpenProfile = onOpenProfile
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                backgroundLayer
                    .frame(width: geo.size.width, height: geo.size.height)

                if currentMode != .player {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }

                LinearGradient(
                    colors: [.black.opacity(0.55), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: geo.size.width, height: 160)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                .allowsHitTesting(false)

                LinearGradient(
                    colors: [.clear, Theme.backgroundColor.opacity(0.7), Theme.backgroundColor],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: geo.size.width, height: 360)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                
                    // top bar
                    Capsule()
                        .fill(.white.opacity(0.3))
                        .frame(width: 36, height: 4)
                        .frame(maxWidth: .infinity)
                        .padding(.top, geo.safeAreaInsets.top + 8)

                    // track info at top for lyrics/comments
                    if currentMode != .player {
                        compactTrackInfo
                            .padding(.leading, 28)
                            .padding(.trailing, 20)
                            .padding(.top, 14)
                            .padding(.bottom, 16)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // middle content
                    if currentMode == .player {
                        Spacer()
                    } else {
                        ZStack {
                            if currentMode == .lyrics {
                                lyricsContent.transition(.opacity)
                            }

                            if currentMode == .comments {
                                commentsContent.transition(.opacity)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    // track info near bottom for player
                    if currentMode == .player {
                        largeTrackInfo
                            .padding(.leading, 28)
                            .padding(.trailing, 20)
                            .padding(.bottom, 20)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // progress + controls
                    VStack(spacing: 20) {
                        progressSection
                        controls
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 20)

                    // tab bar
                    modeTabBar
                        .padding(.horizontal, 28)
                        .padding(.bottom, max(geo.safeAreaInsets.bottom, 16) + 20)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            
            if showNoLyricsToast {
                VStack {
                    HStack(spacing: 10) {
                        Image(systemName: "music.note")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("No lyrics yet")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)

                            Button("Contribute lyrics →") {
                                lyricsContributeURL = URL(string: "https://nichemusic.app/lyrics/contribute")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.accentColor)
                            .buttonStyle(.plain)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, geo.safeAreaInsets.top + 60)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(true)
                .zIndex(200)
            }
            if showLyricsIssueToast {
                VStack {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Something wrong?")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)

                            Button("Suggest a change →") {
                                showLyricsIssueToast = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    lyricsContributeURL = URL(string: "https://nichemusic.app/lyrics/contribute")
                                }
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.accentColor)
                            .buttonStyle(.plain)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, geo.safeAreaInsets.top + 60)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(true)
                .zIndex(200)
            }
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.22), value: showQueue)
        .sheet(item: $lyricsContributeURL) { url in
            SafariView(url: url)
                .ignoresSafeArea()
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: currentMode)
        .onAppear {
            musicPlayer.loadMomentIfNeeded()
            musicPlayer.loadLyricsIfNeeded(using: musicStore)
            musicPlayer.enrichCurrentTrack(using: musicStore)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                hasAppeared = true
            }
        }
        .onChange(of: musicPlayer.currentTrack?.id) { _, _ in
            musicPlayer.loadLyricsIfNeeded(using: musicStore)
            musicPlayer.enrichCurrentTrack(using: musicStore)
            if !(musicPlayer.currentTrack?.hasLyrics ?? false) && currentMode == .lyrics {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                    currentMode = .player
                }
            }
        }
        .onChange(of: musicPlayer.isPlayingDisplay) { _, isPlaying in
            guard hasReadyMoment else { return }
            if isPlaying {
                musicPlayer.momentPlayer?.play()
            } else {
                musicPlayer.momentPlayer?.pause()
            }
        }
        .statusBarHidden()
        .sheet(isPresented: $showQueue) {
            QueueView()
                .environmentObject(musicPlayer)
                .environmentObject(musicStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTrackDetails) {
            if let displayTrack {
                PlayerTrackDetailsSheet(track: displayTrack, onOpenProfile: onOpenProfile)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.clear)
            }
        }
    }
    
    private var compactTrackInfo: some View {
        HStack(spacing: 12) {
            Group {
                if let coverUrl = musicPlayer.currentTrack?.artworkUrl,
                   let url = URL(string: coverUrl) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(0.1))
                        .frame(width: 48, height: 48)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                tappableTrackTitle(font: .system(size: 15, weight: .bold))

                if let displayTrack {
                    TrackFeaturedArtistLine(
                        track: displayTrack,
                        onOpenProfile: onOpenProfile,
                        font: .system(size: 13, weight: .regular),
                        foreground: .white.opacity(0.6)
                    )
                } else {
                    MarqueeText(
                        text: "—",
                        font: .system(size: 13, weight: .regular),
                        foreground: .white.opacity(0.6)
                    )
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

            trackLikeButton(iconSize: 18)
        }
        .frame(maxWidth: .infinity)
    }

    private var largeTrackInfo: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                tappableTrackTitle(font: .system(size: 22, weight: .bold))

                if let displayTrack {
                    TrackFeaturedArtistLine(
                        track: displayTrack,
                        onOpenProfile: onOpenProfile,
                        font: .system(size: 16, weight: .regular),
                        foreground: .white.opacity(0.6)
                    )
                } else {
                    MarqueeText(
                        text: "—",
                        font: .system(size: 16, weight: .regular),
                        foreground: .white.opacity(0.6)
                    )
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

            trackLikeButton(iconSize: 22)
        }
        .frame(maxWidth: .infinity)
    }

    private func trackLikeButton(iconSize: CGFloat) -> some View {
        let isLiked = currentTrackViewer.isLiked
        let isBusy = musicPlayer.currentTrack.map { musicStore.isLikeBusy(trackId: $0.id) } ?? false

        return Button {
            guard let trackId = musicPlayer.currentTrack?.id else { return }
            Task {
                await musicStore.toggleTrackLike(trackId: trackId)
                if let track = musicStore.track(id: trackId) {
                    musicPlayer.syncCurrentTrackDetails(track)
                }
            }
        } label: {
            Image(systemName: isLiked ? "heart.fill" : "heart")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(isLiked ? Theme.accentColor : .white.opacity(0.7))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(isBusy || musicPlayer.currentTrack == nil || session.currentUser == nil)
        .opacity(isBusy ? 0.55 : 1)
    }

    // MARK: Background

    @ViewBuilder
    private var backgroundLayer: some View {
        if hasReadyMoment, let player = musicPlayer.momentPlayer {
            MomentVideoBackground(player: player)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .id("moment-\(musicPlayer.loadedMomentTrackId ?? "none")")
                .transition(.opacity)
        } else {
            if let coverUrl = musicPlayer.currentTrack?.artworkUrl,
               let url = URL(string: coverUrl) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .clipped()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .id("artwork-\(musicPlayer.currentTrack?.id ?? "none")")
                    .transition(.opacity)
            } else {
                Theme.backgroundColor.ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
    }

    private var modeTabBar: some View {
        HStack(spacing: 0) {
            tabButton(icon: "bubble.left.and.bubble.right", mode: .comments)
            tabButton(icon: "play.circle", mode: .player)
            tabButton(icon: "quote.bubble", mode: .lyrics)
        }
        .frame(maxWidth: .infinity)
    }

    private func tabButton(icon: String, mode: PlayerMode) -> some View {
        let isDisabled = mode == .lyrics && !(musicPlayer.currentTrack?.hasLyrics ?? false)
        let isSelected = currentMode == mode

        return Button {
            if isDisabled {
                showToast()
                return
            }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                currentMode = mode
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(
                        isDisabled ? 0.18 : (isSelected ? 1.0 : 0.35)
                    ))
                    .frame(width: 24, height: 24)

                if isSelected {
                    Capsule()
                        .fill(.white)
                        .frame(width: 28, height: 2)
                        .matchedGeometryEffect(id: "tabUnderline", in: modeNamespace)
                } else {
                    Capsule()
                        .fill(.clear)
                        .frame(width: 28, height: 2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func showToast() {
        guard !showNoLyricsToast else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showNoLyricsToast = true
        }
        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.easeOut(duration: 0.3)) {
                showNoLyricsToast = false
            }
        }
    }

    // MARK: Placeholder content views

    private var lyricsContent: some View {
        ZStack(alignment: .bottomTrailing) {
            LyricsView()
                .environmentObject(musicPlayer)

            Button {
                guard !showLyricsIssueToast else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showLyricsIssueToast = true
                }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(.easeOut(duration: 0.3)) {
                        showLyricsIssueToast = false
                    }
                }
            } label: {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
    }

    private var commentsContent: some View {
        TrackCommentsView(showsHeader: false, onOpenProfile: onOpenProfile)
            .environmentObject(musicPlayer)
            .environmentObject(musicStore)
            .environmentObject(session)
    }

    private func tappableTrackTitle(font: Font) -> some View {
        Button {
            guard let trackId = musicPlayer.currentTrack?.id else { return }
            onOpenTrackDetail?(trackId)
        } label: {
            HStack(spacing: 6) {
                MarqueeText(
                    text: musicPlayer.currentTrack?.name ?? "—",
                    font: font,
                    foreground: .white
                )
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                if musicPlayer.currentTrack?.explicit == true {
                    ExplicitBadge()
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                showTrackDetails = true
            }
        )
    }

    // MARK: Progress

    private var progressSection: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.08))
                        .frame(height: 8)

                    Capsule()
                        .fill( isDragging ? .white.opacity(0.9) : .white.opacity(0.6))
                        .frame(
                            width: musicPlayer.duration > 0
                                ? geo.size.width * CGFloat(musicPlayer.currentTime / musicPlayer.duration)
                                : 0,
                            height: 8
                        )
                        .animation(isDragging ? nil : .linear(duration: 0.5), value: musicPlayer.currentTime)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle().size(CGSize(width: geo.size.width, height: 44)))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    isDragging = true
                                }
                                dragStartX = value.startLocation.x
                                dragStartProgress = musicPlayer.duration > 0
                                    ? musicPlayer.currentTime / musicPlayer.duration
                                    : 0
                                musicPlayer.beginScrubbing()
                            }
                            let delta = value.location.x - dragStartX
                            let progress = max(0, min(1, dragStartProgress + delta / geo.size.width))
                            musicPlayer.scrub(progress: progress)
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                                isDragging = false
                            }
                            musicPlayer.endScrubbing()
                        }
                )
            }
            .frame(height: 28)

            HStack {
                Text(formatTime(musicPlayer.currentTime))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.25))
                Spacer()
                Text("-" + formatTime(musicPlayer.remainingTime))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .scaleEffect(isDragging ? 1.06 : 1.0, anchor: .bottom)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
    }

    // MARK: Controls
    private var controls: some View {
        HStack(spacing: 0) {
            playbackModeButton(
                icon: "shuffle",
                isActive: musicPlayer.isShuffleEnabled
            ) {
                musicPlayer.toggleShuffle()
            }

            HStack(spacing: 22) {
                Button {
                    musicPlayer.skipToPrevious()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 64, height: 64)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    withTransaction(Transaction(animation: nil)) {
                        musicPlayer.togglePlayPause()
                    }
                } label: {
                    ZStack {
                        if musicPlayer.isLoading {
                            NicheProgress().scaleEffect(1.2)
                        } else {
                            Image(systemName: musicPlayer.isPlayingDisplay ? "pause.fill" : "play.fill")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundStyle(.white.opacity(0.86))
                                .offset(x: musicPlayer.isPlayingDisplay ? 0 : 3)
                        }
                    }
                    .frame(width: 82, height: 82)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    musicPlayer.skipToNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 64, height: 64)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)

            sideControlButton(icon: "list.bullet") {
                showQueue = true
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func playbackModeButton(
        icon: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isActive ? Theme.accentColor : .white.opacity(0.45))
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func sideControlButton(
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    
    
    // MARK: Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
