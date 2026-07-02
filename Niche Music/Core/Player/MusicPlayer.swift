//
//  MusicPlayer.swift
//  nichemusic
//
//  Created by Ryan Rahman on 5/9/26.
//

// full music player; for testing just support playing a single track but should be easily adaptable later when we add other stuff

import Foundation
import AVFoundation
import MediaPlayer
import Combine
import SwiftUI
import UIKit

struct QueuedTrack: Identifiable, Equatable {
    let id = UUID()
    let track: NicheTrack
    let url: URL
    let source: String?
}

enum PlayerRepeatMode: String, Equatable, Codable {
    case off
    case all
    case one
}


@MainActor
final class MusicPlayer: ObservableObject {
    @Published var currentTrack: NicheTrack?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var currentSource: String?
    @Published private(set) var sessionSource: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isPlayingDisplay: Bool = false
    @Published private(set) var queue: [QueuedTrack] = []
    @Published private(set) var history: [QueuedTrack] = []
    @Published private(set) var isShuffleEnabled = false
    @Published private(set) var repeatMode: PlayerRepeatMode = .off

    private let preferencesStore = PlaybackPreferencesStore.shared
    private var sessionContext: PlaybackSessionContext?
    private let player = AVPlayer()
    private var sessionOrder: [QueuedTrack] = []
    private var preShuffleQueue: [QueuedTrack]?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var wasPlayingBeforeScrub = false
    private var isScrubbing = false
    
    @Published var momentPlayer: AVPlayer?
    @Published var momentReady = false
    @Published var loadedMomentTrackId: String?
    
    // lyrics
    @Published var lyrics: TrackLyrics? = nil
    @Published var currentLyricIndex: Int = 0
    @Published var lyricsLoading: Bool = false
    @Published var lyricsError: Bool = false
    private var lyricsTrackId: String? = nil
    
    
    
    private var momentEndObserver: NSObjectProtocol?
    private var momentLoadTask: Task<Void, Never>?
    private var enrichingTrackId: String?
    
    @Published var dominantColor: Color = Color(white: 0.08)
    
    var remainingTime: Double {
        max(0, duration - currentTime)
    }


    init() {
        setupAudioSession()
        setupRemoteCommands()
        addTimeObserver()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }

        statusObserver?.invalidate()
    }

    // MARK: - Public

    func load(track: NicheTrack, url: URL, source: String? = nil, autoplay: Bool = true) {
        cleanupCurrentItem()

        let isNewTrack = currentTrack?.id != track.id
        currentTrack = track
        if isNewTrack {
            enrichingTrackId = nil
        }
        currentSource = source ?? sessionSource
        currentTime = 0
        duration = 0
        isLoading = true
        errorMessage = nil

        let item = AVPlayerItem(url: url)
        playerItem = item
        player.replaceCurrentItem(with: item)

        statusObserver = item.observe(\.status, options: [.new, .initial]) { item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                switch item.status {
                case .readyToPlay:
                    self.isLoading = false
                    self.duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
                    self.updateNowPlaying()

                    if autoplay {
                        self.play()
                    }

                case .failed:
                    self.isLoading = false
                    self.isPlaying = false
                    self.errorMessage = item.error?.localizedDescription ?? "Failed to load track"

                default:
                    break
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.handleTrackEnded()
            }
        }

        clearMoment()
        loadMomentIfNeeded()
    }

    func play() {
        guard player.currentItem != nil else { return }
        player.play()
        isPlaying = true
        if !wasPlayingBeforeScrub || !isScrubbing {
            isPlayingDisplay = true
        }
        updateNowPlayingPlaybackState()
    }

    func pause() {
        player.pause()
        isPlaying = false
        if !isScrubbing {
            isPlayingDisplay = false
        }
        updateNowPlayingPlaybackState()
    }

    func pauseAllPlayback() {
        pause()
        clearMoment()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
            isPlayingDisplay = false
        } else {
            play()
            isPlayingDisplay = true
        }
    }

    func seek(to time: TimeInterval) {
        let safeTime = max(0, min(time, duration))
        let cmTime = CMTime(seconds: safeTime, preferredTimescale: 600)

        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = safeTime
        updateNowPlayingPlaybackState()
    }

    func seekProgress(_ progress: Double) {
        guard duration > 0 else { return }
        seek(to: duration * max(0, min(progress, 1)))
    }

    func stop(clearQueue: Bool = true, clearHistory: Bool = true) {
        player.pause()
        cleanupCurrentItem()
        clearMoment()

        if clearQueue {
            queue.removeAll()
            sessionOrder.removeAll()
            preShuffleQueue = nil
        }

        if clearHistory {
            history.removeAll()
        }

        currentTrack = nil
        currentSource = nil
        sessionSource = nil
        persistCurrentPreferences()
        sessionContext = nil
        currentTime = 0
        duration = 0
        isPlaying = false
        isPlayingDisplay = false
        isLoading = false
        errorMessage = nil

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Setup

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.allowBluetoothA2DP]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            #if DEBUG
            print("[MusicPlayer] Audio session error:", error)
            #endif
        }
    }

    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { time in
            Task { @MainActor [weak self] in
                guard let self else { return }

                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                self.updateCurrentLyricIndex()

                if let itemDuration = self.player.currentItem?.duration.seconds,
                   itemDuration.isFinite,
                   itemDuration > 0 {
                    self.duration = itemDuration
                }

                self.updateNowPlayingPlaybackState()
            }
        }
    }

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.play()
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.pause()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.togglePlayPause()
            }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }

            Task { @MainActor in
                self?.seek(to: event.positionTime)
            }

            return .success
        }
        
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { _ in
            Task { @MainActor [weak self] in
                self?.skipToNext()
            }
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { _ in
            Task { @MainActor [weak self] in
                self?.skipToPrevious()
            }
            return .success
        }
    }

    // MARK: - Private

    private func handleTrackEnded() {
        if repeatMode == .one {
            seek(to: 0)
            play()
            return
        }

        if playNextInQueue(addCurrentToHistory: true) {
            return
        }

        if repeatMode == .all, restartSessionForRepeatAll() {
            return
        }

        seek(to: 0)
        pause()
    }

    @discardableResult
    private func restartSessionForRepeatAll() -> Bool {
        guard !sessionOrder.isEmpty else { return false }

        history.removeAll()

        var upcoming = sessionOrder
        if isShuffleEnabled {
            upcoming.shuffle()
        }

        let first = upcoming.removeFirst()
        queue = upcoming
        load(
            track: first.track,
            url: first.url,
            source: first.source,
            autoplay: true
        )
        return true
    }

    private func cleanupCurrentItem() {
        statusObserver?.invalidate()
        statusObserver = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        player.replaceCurrentItem(with: nil)
        playerItem = nil
        lyrics = nil
        lyricsTrackId = nil
        currentLyricIndex = 0
    }

    private func updateNowPlaying() {
        guard let track = currentTrack else { return }
        
        let displayTitle = track.explicit ? "\(track.name) 🅴" : track.name
        
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: displayTitle,
            MPMediaItemPropertyArtist: track.displayArtistLine,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        if let source = currentSource {
            info[MPMediaItemPropertyAlbumTitle] = source
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        Task {
            await loadNowPlayingArtwork(from: track.artworkUrl)
        }
    }

    private func updateNowPlayingPlaybackState() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
            updateNowPlaying()
            return
        }

        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPMediaItemPropertyPlaybackDuration] = duration

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    private func loadNowPlayingArtwork(from artworkUrl: String) async {
        guard let url = URL(string: artworkUrl) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            guard let image = UIImage(data: data) else { return }

            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in
                image
            }

            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        } catch {
            #if DEBUG
            print("[MusicPlayer] Failed to load artwork:", error)
            #endif
        }
    }
    
    func beginScrubbing() {
        isScrubbing = true
        wasPlayingBeforeScrub = isPlaying
        pause()
    }

    func endScrubbing() {
        isScrubbing = false
        if wasPlayingBeforeScrub {
            play()
        }
    }

    func scrub(progress: Double) {
        let time = progress * duration
        // seek the AVPlayer without resuming
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero)
        // manually update currentTime so the UI reflects it
        currentTime = time
    }
    
    /// queue
    func playNow(track: NicheTrack, url: URL, source: String? = nil, resetSession: Bool = true) {
        let entry = QueuedTrack(track: track, url: url, source: source)

        if resetSession {
            history.removeAll()
            queue.removeAll()
            sessionOrder = [entry]
            preShuffleQueue = nil
            sessionSource = source
            activateSession(.general)
        }

        load(track: track, url: url, source: source, autoplay: true)
    }

    func syncCurrentTrackDetails(_ track: NicheTrack) {
        guard currentTrack?.id == track.id else { return }
        guard currentTrack != track else { return }
        currentTrack = track
        updateNowPlaying()
    }

    func enrichCurrentTrack(using musicStore: MusicStore) {
        guard let trackId = currentTrack?.id else { return }

        if let cached = musicStore.track(id: trackId) {
            syncCurrentTrackDetails(cached)
            if cached.credits != nil, musicStore.hasViewerContext(for: trackId) {
                return
            }
        }

        guard enrichingTrackId != trackId else { return }
        enrichingTrackId = trackId

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.enrichingTrackId == trackId {
                    self.enrichingTrackId = nil
                }
            }

            guard self.currentTrack?.id == trackId else { return }

            guard let detail = try? await musicStore.fetchTrackDetail(id: trackId) else { return }
            self.syncCurrentTrackDetails(detail.track)
        }
    }

    func addToQueue(track: NicheTrack, url: URL, source: String? = nil) {
        let resolvedSource = source ?? sessionSource
        let entry = QueuedTrack(track: track, url: url, source: resolvedSource)
        queue.append(entry)
        sessionOrder.append(entry)
    }

    func playNext(track: NicheTrack, url: URL, source: String? = nil) {
        let resolvedSource = source ?? sessionSource
        let entry = QueuedTrack(track: track, url: url, source: resolvedSource)
        queue.insert(entry, at: 0)
        sessionOrder.append(entry)
    }

    func playPlaylist(
        _ entries: [QueuedTrack],
        startIndex: Int,
        source sessionSource: String? = nil,
        playlistId: String? = nil
    ) {
        guard entries.indices.contains(startIndex) else { return }

        activateSession(playlistId.map { .playlist(id: $0) } ?? .general)

        self.sessionSource = sessionSource

        let resolvedEntries = entries.map { entry in
            QueuedTrack(
                track: entry.track,
                url: entry.url,
                source: sessionSource ?? entry.source
            )
        }

        history.removeAll()
        queue.removeAll()
        sessionOrder = resolvedEntries
        preShuffleQueue = nil

        if startIndex > 0 {
            history.append(contentsOf: resolvedEntries.prefix(startIndex))
        }

        let current = resolvedEntries[startIndex]
        load(
            track: current.track,
            url: current.url,
            source: current.source,
            autoplay: true
        )

        var upcoming = startIndex + 1 < resolvedEntries.count
            ? Array(resolvedEntries[(startIndex + 1)...])
            : []
        if isShuffleEnabled {
            preShuffleQueue = upcoming
            upcoming.shuffle()
        } else {
            preShuffleQueue = nil
        }
        queue = upcoming
    }

    func toggleShuffle() {
        isShuffleEnabled.toggle()

        if isShuffleEnabled {
            preShuffleQueue = queue
            queue.shuffle()
        } else {
            restoreQueueOrder()
        }

        persistCurrentPreferences()
    }

    private func restoreQueueOrder() {
        if let preShuffleQueue {
            queue = preShuffleQueue
            self.preShuffleQueue = nil
            return
        }

        let startIndex = history.count + (currentTrack == nil ? 0 : 1)
        guard startIndex < sessionOrder.count else {
            queue = []
            return
        }
        queue = Array(sessionOrder[startIndex...])
    }

    func toggleRepeat() {
        repeatMode = switch repeatMode {
        case .off: .all
        case .all: .one
        case .one: .off
        }

        persistCurrentPreferences()
    }

    private func activateSession(_ context: PlaybackSessionContext) {
        if let previous = sessionContext {
            if previous != context {
                persistCurrentPreferences(for: previous)
                sessionContext = context
                applyStoredPreferences(for: context)
            }
        } else {
            sessionContext = context
            applyStoredPreferences(for: context)
        }
    }

    private func applyStoredPreferences(for context: PlaybackSessionContext) {
        let preferences = preferencesStore.load(for: context)
        isShuffleEnabled = preferences.shuffle
        repeatMode = preferences.repeatMode
    }

    private func persistCurrentPreferences(for context: PlaybackSessionContext? = nil) {
        guard let activeContext = context ?? sessionContext else { return }

        preferencesStore.save(
            PlaybackPreferences(shuffle: isShuffleEnabled, repeatMode: repeatMode),
            for: activeContext
        )
    }

    func jumpToQueuedTrack(_ item: QueuedTrack) {
        guard let index = queue.firstIndex(where: { $0.id == item.id }) else { return }

        if let current = makeCurrentQueuedTrack() {
            history.append(current)
        }

        history.append(contentsOf: queue.prefix(index))

        let selected = queue[index]
        queue.removeFirst(index + 1)

        load(
            track: selected.track,
            url: selected.url,
            source: selected.source,
            autoplay: true
        )
    }

    func skipToNext() {
        if playNextInQueue(addCurrentToHistory: true) {
            return
        }

        if repeatMode == .all, restartSessionForRepeatAll() {
            return
        }

        stop(clearQueue: false)
    }

    func skipToPrevious() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }

        guard let previous = history.popLast() else {
            seek(to: 0)
            return
        }

        if let current = makeCurrentQueuedTrack() {
            queue.insert(current, at: 0)
        }

        load(
            track: previous.track,
            url: previous.url,
            source: previous.source,
            autoplay: true
        )
    }

    @discardableResult
    private func playNextInQueue(addCurrentToHistory: Bool) -> Bool {
        guard !queue.isEmpty else { return false }

        if addCurrentToHistory, let current = makeCurrentQueuedTrack() {
            history.append(current)
        }

        let next = queue.removeFirst()

        load(
            track: next.track,
            url: next.url,
            source: next.source,
            autoplay: true
        )

        return true
    }

    private func makeCurrentQueuedTrack() -> QueuedTrack? {
        guard let currentTrack,
              let item = player.currentItem,
              let asset = item.asset as? AVURLAsset else {
            return nil
        }

        return QueuedTrack(
            track: currentTrack,
            url: asset.url,
            source: currentSource ?? sessionSource
        )
    }
    
    
    
    /// moments
    func loadMomentIfNeeded() {
        guard let track = currentTrack,
              let momentUrl = track.momentUrl,
              let url = URL(string: momentUrl) else {
            clearMoment()
            return
        }

        if momentReady, loadedMomentTrackId == track.id {
            momentPlayer?.play()
            return
        }

        clearMoment()

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)

        player.isMuted = true
        player.actionAtItemEnd = .none
        player.preventsDisplaySleepDuringVideoPlayback = false

        momentPlayer = player
        loadedMomentTrackId = track.id
        momentReady = false

        momentLoadTask = Task { [weak self, weak player, weak item] in
            guard let item else { return }

            do {
                _ = try await item.asset.load(.tracks)

                await MainActor.run {
                    guard let self,
                          self.currentTrack?.id == track.id,
                          self.loadedMomentTrackId == track.id else { return }

                    self.momentReady = true
                    player?.play()

                    self.momentEndObserver = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: item,
                        queue: .main
                    ) { [weak player] _ in
                        player?.seek(to: .zero)
                        player?.play()
                    }
                }
            } catch {
                await MainActor.run {
                    if self?.loadedMomentTrackId == track.id {
                        self?.clearMoment()
                    }
                }
            }
        }
    }

    func clearMoment() {
        momentLoadTask?.cancel()
        momentLoadTask = nil

        if let momentEndObserver {
            NotificationCenter.default.removeObserver(momentEndObserver)
            self.momentEndObserver = nil
        }

        momentPlayer?.pause()
        momentPlayer = nil
        momentReady = false
        loadedMomentTrackId = nil
    }
    
    /// lyrics
    
    
    func loadLyricsIfNeeded(using musicStore: MusicStore) {
        guard let track = currentTrack else { return }
        guard lyricsTrackId != track.id else { return }

        lyricsTrackId = track.id
        lyrics = nil
        currentLyricIndex = 0
        lyricsLoading = true
        lyricsError = false

        Task { @MainActor [weak self] in
            guard let self else { return }

            let result = await musicStore.loadLyrics(trackId: track.id)

            guard self.currentTrack?.id == track.id else { return }

            switch result {
            case .found(let loadedLyrics):
                self.lyrics = loadedLyrics
                self.lyricsLoading = false
                self.lyricsError = false
                self.updateCurrentLyricIndex()

            case .notFound:
                self.lyrics = nil
                self.lyricsLoading = false
                self.lyricsError = false
                // important: keep lyricsTrackId as track.id
                // so FullPlayerView does not refetch every open
            }
        }
    }
    
    func updateCurrentLyricIndex() {
        guard let lines = lyrics?.lyricsJson, !lines.isEmpty else { return }
        let now = currentTime
        
        // find the last line whose timestamp is <= currentTime
        var idx = 0
        for (i, line) in lines.enumerated() {
            if line.timeSeconds <= now {
                idx = i
            } else {
                break
            }
        }
        currentLyricIndex = idx
    }
}
