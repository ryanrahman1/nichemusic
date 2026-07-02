//
//  FeedPlayerCache.swift
//  Niche Music
//

import AVFoundation
import AVKit
import UIKit
import Combine

@MainActor
final class FeedPlayerCache: ObservableObject {
    static let shared = FeedPlayerCache()

    private var players: [String: AVPlayer] = [:]
    private var endObservers: [String: Any] = [:]
    private var boundaryObservers: [String: Any] = [:]
    private var timeObserver: Any?
    private var observedPreviewCacheKey: String?
    private let maxCached = 10

    @Published private(set) var activePostId: String?
    private(set) var activePreviewCacheKey: String?
    private(set) var activeUploadedVideoURL: String?
    private(set) var activeMomentURL: String?
    @Published private(set) var isPreviewPausedByUser = false
    @Published private(set) var previewPlaybackProgress: Double = 0
    private var lastPublishedPreviewProgress: Double = 0
    private var isMusicPlayerActive = false
    private var isSuspendedForAppLifecycle = false

    private init() {
        let center = NotificationCenter.default
        center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                FeedPlayerCache.shared.suspendForAppBackground()
            }
        }
        center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                FeedPlayerCache.shared.suspendForAppBackground()
            }
        }
        center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                FeedPlayerCache.shared.clearAppBackgroundSuspension()
            }
        }
    }

    func suspendForAppBackground() {
        guard !isSuspendedForAppLifecycle else { return }
        isSuspendedForAppLifecycle = true
        stopPreviewProgressObservation()
        players.values.forEach { $0.pause() }
    }

    func clearAppBackgroundSuspension() {
        isSuspendedForAppLifecycle = false
    }

    var canPlayFeedMedia: Bool {
        !isSuspendedForAppLifecycle
    }

    func stopAll() {
        activePostId = nil
        activePreviewCacheKey = nil
        activeUploadedVideoURL = nil
        activeMomentURL = nil
        isPreviewPausedByUser = false
        stopPreviewProgressObservation()
        players.values.forEach { $0.pause() }
    }

    func pauseAll() {
        activePostId = nil
        activePreviewCacheKey = nil
        activeUploadedVideoURL = nil
        activeMomentURL = nil
        stopPreviewProgressObservation()
        players.values.forEach { $0.pause() }
    }

    func setActivePost(
        postId: String?,
        media: FeedActivePostMedia,
        shouldPlay: Bool,
        musicPlayerActive: Bool
    ) {
        players.values.forEach { $0.pause() }

        isMusicPlayerActive = musicPlayerActive

        guard shouldPlay, let postId else {
            activePostId = nil
            activePreviewCacheKey = nil
            activeUploadedVideoURL = nil
            activeMomentURL = nil
            stopPreviewProgressObservation()
            return
        }

        activePostId = postId
        activePreviewCacheKey = media.previewCacheKey
        activeUploadedVideoURL = media.uploadedVideoURL
        activeMomentURL = media.momentURL

        if let previewCacheKey = media.previewCacheKey,
           let previewKind = media.previewKind,
           !musicPlayerActive,
           !isPreviewPausedByUser,
           canPlayFeedMedia {
            let player = player(forCacheKey: previewCacheKey, sourceURL: sourceURL(for: previewCacheKey), kind: previewKind)
            player.isMuted = false
            player.play()
            startPreviewProgressObservation(for: previewCacheKey, kind: previewKind)
        } else if let previewCacheKey = media.previewCacheKey {
            players[previewCacheKey]?.pause()
            stopPreviewProgressObservation()
        } else {
            stopPreviewProgressObservation()
        }

        if let momentURL = media.momentURL, canPlayFeedMedia {
            let cacheKey = FeedPlayerMediaKind.moment.cacheKey(for: momentURL)
            let player = player(forCacheKey: cacheKey, sourceURL: momentURL, kind: .moment)
            player.isMuted = true
            player.play()
        }

        if let uploadedVideoURL = media.uploadedVideoURL, canPlayFeedMedia {
            let player = player(forCacheKey: uploadedVideoURL, sourceURL: uploadedVideoURL, kind: .uploadedVideo)
            player.isMuted = musicPlayerActive || media.previewCacheKey != nil
            player.play()
        }
    }

    func setPreviewPausedByUser(_ paused: Bool) {
        isPreviewPausedByUser = paused
        guard let previewCacheKey = activePreviewCacheKey else { return }
        if paused {
            players[previewCacheKey]?.pause()
            stopPreviewProgressObservation()
        } else if canPlayFeedMedia {
            players[previewCacheKey]?.play()
            let kind = FeedPlayerMediaKind.kind(for: previewCacheKey) ?? .catalogPreview
            startPreviewProgressObservation(for: previewCacheKey, kind: kind)
        }
    }

    func togglePreviewPaused() {
        setPreviewPausedByUser(!isPreviewPausedByUser)
    }

    func resetPreviewPauseState() {
        isPreviewPausedByUser = false
    }

    func player(for urlString: String) -> AVPlayer {
        if let existing = players[urlString] {
            return existing
        }

        let kind = FeedPlayerMediaKind.kind(for: urlString) ?? .uploadedVideo
        let sourceURL = sourceURL(for: urlString)
        return player(forCacheKey: urlString, sourceURL: sourceURL, kind: kind)
    }

    func prefetch(media: FeedActivePostMedia) {
        if let cacheKey = media.previewCacheKey, let kind = media.previewKind {
            _ = player(
                forCacheKey: cacheKey,
                sourceURL: sourceURL(for: cacheKey),
                kind: kind
            )
        }

        if let momentURL = media.momentURL {
            let cacheKey = FeedPlayerMediaKind.moment.cacheKey(for: momentURL)
            _ = player(forCacheKey: cacheKey, sourceURL: momentURL, kind: .moment)
        }

        if let uploadedVideoURL = media.uploadedVideoURL {
            _ = player(forCacheKey: uploadedVideoURL, sourceURL: uploadedVideoURL, kind: .uploadedVideo)
        }
    }

    func prefetch(urlString: String, kind: FeedPlayerMediaKind? = nil) {
        let resolvedKind = kind ?? FeedPlayerMediaKind.kind(for: urlString) ?? .uploadedVideo
        let source = sourceURL(for: urlString)
        let cacheKey = resolvedKind.cacheKey(for: source)
        guard players[cacheKey] == nil else { return }
        _ = player(forCacheKey: cacheKey, sourceURL: source, kind: resolvedKind)
    }

    private func player(forCacheKey cacheKey: String, sourceURL: String, kind: FeedPlayerMediaKind) -> AVPlayer {
        if let existing = players[cacheKey] {
            return existing
        }

        let player = makePlayer(forCacheKey: cacheKey, sourceURL: sourceURL, kind: kind)
        players[cacheKey] = player
        evictIfNeeded()
        return player
    }

    private func makePlayer(forCacheKey cacheKey: String, sourceURL: String, kind: FeedPlayerMediaKind) -> AVPlayer {
        guard let url = URL(string: sourceURL) else {
            return AVPlayer()
        }

        let item = makePlayerItem(url: url, kind: kind)
        let player = AVPlayer(playerItem: item)
        configureFeedPlayer(player, kind: kind)
        attachLoopObserver(cacheKey: cacheKey, item: item, player: player, kind: kind)
        return player
    }

    private func makePlayerItem(url: URL, kind: FeedPlayerMediaKind) -> AVPlayerItem {
        switch kind {
        case .nichePreview:
            let options: [String: Any] = [
                "AVURLAssetHTTPHeaderFieldsKey": [
                    "Range": "bytes=0-\(FeedPreviewAudio.nicheRangeByteLength)"
                ]
            ]
            let asset = AVURLAsset(url: url, options: options)
            return AVPlayerItem(asset: asset)
        default:
            return AVPlayerItem(url: url)
        }
    }

    private func configureFeedPlayer(_ player: AVPlayer, kind: FeedPlayerMediaKind) {
        player.audiovisualBackgroundPlaybackPolicy = .pauses
        player.isMuted = kind == .moment
    }

    private func attachLoopObserver(cacheKey: String, item: AVPlayerItem, player: AVPlayer, kind: FeedPlayerMediaKind) {
        if let existing = endObservers[cacheKey] {
            NotificationCenter.default.removeObserver(existing)
        }
        if let existing = boundaryObservers.removeValue(forKey: cacheKey) {
            player.removeTimeObserver(existing)
        }

        endObservers[cacheKey] = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak player] _ in
            Task { @MainActor in
                guard let self, let player else { return }
                guard self.shouldLoop(cacheKey: cacheKey) else { return }
                guard self.canPlayFeedMedia else { return }
                self.restartLoop(player: player, cacheKey: cacheKey, kind: kind)
            }
        }

        if kind == .nichePreview {
            let boundary = CMTime(seconds: FeedPreviewAudio.nicheMaxSeconds, preferredTimescale: 600)
            boundaryObservers[cacheKey] = player.addBoundaryTimeObserver(
                forTimes: [NSValue(time: boundary)],
                queue: .main
            ) { [weak self, weak player] in
                Task { @MainActor in
                    guard let self, let player else { return }
                    guard self.activePreviewCacheKey == cacheKey else { return }
                    guard self.canPlayFeedMedia else { return }
                    self.restartLoop(player: player, cacheKey: cacheKey, kind: kind)
                }
            }
        }
    }

    private func shouldLoop(cacheKey: String) -> Bool {
        cacheKey == activePreviewCacheKey && !isPreviewPausedByUser
            || cacheKey == activeUploadedVideoURL
            || (activeMomentURL.map { FeedPlayerMediaKind.moment.cacheKey(for: $0) } == cacheKey)
    }

    private func restartLoop(player: AVPlayer, cacheKey: String, kind: FeedPlayerMediaKind) {
        if kind == .uploadedVideo {
            player.isMuted = isMusicPlayerActive || activePreviewCacheKey != nil
        } else if kind == .moment {
            player.isMuted = true
        } else {
            player.isMuted = false
            if cacheKey == activePreviewCacheKey {
                lastPublishedPreviewProgress = 0
                previewPlaybackProgress = 0
            }
        }
        player.seek(to: .zero)
        player.play()
    }

    private func startPreviewProgressObservation(for cacheKey: String, kind: FeedPlayerMediaKind) {
        guard observedPreviewCacheKey != cacheKey || timeObserver == nil else { return }
        stopPreviewProgressObservation()

        let player = player(forCacheKey: cacheKey, sourceURL: sourceURL(for: cacheKey), kind: kind)
        observedPreviewCacheKey = cacheKey

        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, self.observedPreviewCacheKey == cacheKey else { return }

                let currentSeconds = time.seconds
                guard currentSeconds.isFinite else { return }

                let durationSeconds: Double
                if kind == .nichePreview {
                    durationSeconds = FeedPreviewAudio.nicheMaxSeconds
                } else if let itemDuration = player.currentItem?.duration.seconds,
                          itemDuration.isFinite,
                          itemDuration > 0 {
                    durationSeconds = itemDuration
                } else {
                    return
                }

                let progress = min(1, max(0, currentSeconds / durationSeconds))
                guard abs(progress - self.lastPublishedPreviewProgress) >= 0.02
                    || progress == 0
                    || progress >= 1 else { return }

                self.lastPublishedPreviewProgress = progress
                self.previewPlaybackProgress = progress
            }
        }
    }

    private func stopPreviewProgressObservation() {
        if let timeObserver, let cacheKey = observedPreviewCacheKey, let player = players[cacheKey] {
            player.removeTimeObserver(timeObserver)
        }
        self.timeObserver = nil
        observedPreviewCacheKey = nil
        lastPublishedPreviewProgress = 0
        previewPlaybackProgress = 0
    }

    private func sourceURL(for cacheKey: String) -> String {
        if FeedPreviewAudio.isNichePreviewCacheKey(cacheKey) {
            return String(cacheKey.dropFirst("niche-preview:".count))
        }
        if FeedPreviewAudio.isMomentCacheKey(cacheKey) {
            return String(cacheKey.dropFirst("moment:".count))
        }
        return cacheKey
    }

    private func evictIfNeeded() {
        guard players.count > maxCached else { return }

        let protected = Set([
            activePreviewCacheKey,
            activeUploadedVideoURL,
            activeMomentURL.map { FeedPlayerMediaKind.moment.cacheKey(for: $0) }
        ].compactMap { $0 })

        let inactive = players.filter { key, player in
            !protected.contains(key) && player.timeControlStatus != .playing
        }
        guard let key = inactive.first?.key else { return }

        if let observer = endObservers.removeValue(forKey: key) {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = boundaryObservers.removeValue(forKey: key),
           let player = players[key] {
            player.removeTimeObserver(observer)
        }
        players.removeValue(forKey: key)
    }
}
