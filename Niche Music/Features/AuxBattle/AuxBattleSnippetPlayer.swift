//
//  AuxBattleSnippetPlayer.swift
//  Niche Music
//

import AVFoundation
import Combine

@MainActor
final class AuxBattleSnippetPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var countdown: Int?
    @Published private(set) var activeSide: String?

    private var player: AVPlayer?
    private var stopTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var timeObserver: Any?

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

    func playMatchupSnippet(
        submission: AuxBattleSubmission,
        side: String,
        countdownEndsAt: String?,
        durationMs: Int?
    ) {
        stop()
        activeSide = side

        let snippetMs = durationMs ?? submission.snippetDurationMs ?? 15_000
        let startMs = submission.snippetStartMs ?? 0

        guard let urlString = submission.musicUrl, let url = URL(string: urlString) else { return }

        let endsAt: Date
        if let countdownEndsAt, let parsed = Self.parseISO8601(countdownEndsAt) {
            endsAt = parsed
        } else {
            endsAt = Date().addingTimeInterval(3)
        }

        let wait = max(0, endsAt.timeIntervalSinceNow)
        countdown = Self.countdownValue(until: endsAt)

        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let remaining = Self.countdownValue(until: endsAt)
                if remaining == nil {
                    countdown = nil
                    break
                }
                countdown = remaining
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        stopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.countdown = nil
            self?.startPlayback(url: url, startMs: startMs, durationMs: snippetMs)
        }
    }

    func previewSnippet(url: URL, startMs: Int, durationMs: Int) {
        stop()
        activeSide = nil
        startPlayback(url: url, startMs: startMs, durationMs: durationMs)
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
        activeSide = nil

        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        player?.pause()
        player = nil
        isPlaying = false
    }

    private func startPlayback(url: URL, startMs: Int, durationMs: Int) {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player

        let startSeconds = CMTime(seconds: Double(startMs) / 1000, preferredTimescale: 600)
        player.seek(to: startSeconds, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
        isPlaying = true

        stopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(durationMs) * 1_000_000)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    private static func parseISO8601(_ value: String) -> Date? {
        if let date = iso8601WithFractional.date(from: value) { return date }
        return iso8601Standard.date(from: value)
    }

    private static func countdownValue(until endsAt: Date) -> Int? {
        let remaining = endsAt.timeIntervalSinceNow
        guard remaining > 0 else { return nil }
        return max(1, Int(ceil(remaining)))
    }

    deinit {
        stopTask?.cancel()
        countdownTask?.cancel()
    }
}
