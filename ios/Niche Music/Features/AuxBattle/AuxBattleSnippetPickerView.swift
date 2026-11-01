//
//  AuxBattleSnippetPickerView.swift
//  Niche Music
//

import Kingfisher
import SwiftUI

struct AuxBattleSnippetPickerView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var store: AuxBattleStore
    @ObservedObject var snippetPlayer: AuxBattleSnippetPlayer

    let pick: AuxSongPickSource
    let snippetLengthSeconds: Int
    let onSuccess: () -> Void

    @State private var musicURL: URL?
    @State private var trackDurationMs: Int = 0
    @State private var startMs: Double = 0
    @State private var isLoadingTrack = true
    @State private var isSubmitting = false
    @State private var loadError: String?
    @State private var submitError: String?

    private let api = APIClient.shared

    private var snippetLengthMs: Int { snippetLengthSeconds * 1000 }
    private var maxStartMs: Int { max(0, trackDurationMs - snippetLengthMs) }
    private var canPreview: Bool { musicURL != nil && !isLoadingTrack }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundColor.ignoresSafeArea()

                if isLoadingTrack {
                    ProgressView("Loading track…")
                        .tint(.white)
                        .foregroundStyle(Theme.textSecondaryColor)
                } else if let loadError {
                    errorState(loadError)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 28) {
                            artworkView

                            VStack(spacing: 6) {
                                Text(pick.name)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)

                                Text(pick.artistName)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Theme.textSecondaryColor)
                            }
                            .padding(.horizontal, 20)

                            snippetSection

                            if let submitError {
                                Text(submitError)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.red.opacity(0.85))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                            }

                            VStack(spacing: 12) {
                                AuxSecondaryButton(title: snippetPlayer.isPlaying ? "Playing…" : "Preview snippet", disabled: !canPreview) {
                                    previewSnippet()
                                }

                                AuxPrimaryButton(
                                    title: "Lock in snippet",
                                    isLoading: isSubmitting,
                                    disabled: !canPreview
                                ) {
                                    Task { await lockInSnippet() }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Choose snippet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        snippetPlayer.stop()
                        dismiss()
                    }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .interactiveDismissDisabled(isSubmitting)
        .task {
            await loadTrackDetails()
        }
        .onDisappear {
            snippetPlayer.stop()
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        Group {
            if let urlString = pick.artworkUrl,
               let url = URL(string: urlString.replacingOccurrences(of: "{w}x{h}", with: "300x300")) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.08)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                    }
            }
        }
        .frame(width: 160, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var snippetSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(snippetLengthSeconds)s snippet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Text("\(timeLabel(ms: Int(startMs))) – \(timeLabel(ms: Int(startMs) + snippetLengthMs))")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textSecondaryColor)
            }

            VStack(spacing: 10) {
                Slider(
                    value: $startMs,
                    in: 0...Double(max(maxStartMs, 1)),
                    step: 500,
                    onEditingChanged: { editing in
                        if !editing {
                            AuxBattleHaptics.selection()
                        }
                    }
                )
                .tint(Theme.accentColor)
                .disabled(maxStartMs <= 0)

                HStack {
                    Text(timeLabel(ms: 0))
                    Spacer()
                    Text(timeLabel(ms: trackDurationMs))
                }
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textSecondaryColor)
            }

            Text("Scrub to pick which part of the song plays during the battle.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textSecondaryColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondaryColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Button("Try again") {
                Task { await loadTrackDetails() }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
        }
    }

    private func loadTrackDetails() async {
        isLoadingTrack = true
        loadError = nil
        submitError = nil

        switch pick {
        case .niche(let track):
            if let urlString = track.musicUrl, !urlString.isEmpty, let url = URL(string: urlString) {
                musicURL = url
                trackDurationMs = max(track.durationMs ?? 0, snippetLengthMs)
            } else {
                do {
                    let response: NicheTrackResponse = try await api.request(
                        Endpoints.nicheSong(id: track.id),
                        method: .get
                    )
                    guard !response.track.musicUrl.isEmpty, let url = URL(string: response.track.musicUrl) else {
                        loadError = "This track doesn't have playable audio."
                        isLoadingTrack = false
                        return
                    }
                    musicURL = url
                    trackDurationMs = max(response.track.durationMs, snippetLengthMs)
                } catch {
                    loadError = error.localizedDescription
                    isLoadingTrack = false
                    return
                }
            }

        case .apple(_, _, _, _, _, let previewUrl, let durationMs):
            guard let previewUrl, !previewUrl.isEmpty, let url = URL(string: previewUrl) else {
                loadError = "This song doesn't have a preview available."
                isLoadingTrack = false
                return
            }
            musicURL = url
            trackDurationMs = max(durationMs ?? 30_000, snippetLengthMs)
        }

        startMs = 0
        isLoadingTrack = false
    }

    private func previewSnippet() {
        guard let url = musicURL else { return }
        AuxBattleHaptics.impact(.light)
        snippetPlayer.previewSnippet(
            url: url,
            startMs: Int(startMs),
            durationMs: snippetLengthMs
        )
    }

    private func lockInSnippet() async {
        submitError = nil
        isSubmitting = true
        snippetPlayer.stop()

        let success: Bool
        switch pick {
        case .niche(let track):
            success = await store.submitSong(
                source: .niche,
                nicheTrackId: track.id,
                trackId: nil,
                snippetStartMs: Int(startMs)
            )
        case .apple(let trackId, _, _, _, _, _, _):
            success = await store.submitSong(
                source: .apple,
                nicheTrackId: nil,
                trackId: trackId,
                snippetStartMs: Int(startMs)
            )
        }

        isSubmitting = false

        if success {
            AuxBattleHaptics.success()
            onSuccess()
            dismiss()
        } else {
            AuxBattleHaptics.error()
            submitError = store.lastError ?? "Couldn't lock in your song."
        }
    }

    private func timeLabel(ms: Int) -> String {
        let totalSeconds = max(0, ms / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
