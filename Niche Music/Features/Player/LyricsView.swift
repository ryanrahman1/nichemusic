//
//  LyricsView.swift
//  Niche Music
//
//  Created by Ryan Rahman on 5/24/26.
//

import SwiftUI

struct LyricsView: View {
    @EnvironmentObject var musicPlayer: MusicPlayer
    @State private var userScrolling = false
    @State private var scrollResetTask: Task<Void, Never>? = nil
    @State private var showingTranslation = false

    var body: some View {
        Group {
            if musicPlayer.lyricsLoading {
                ProgressView()
                    .tint(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if musicPlayer.lyricsError {
                Text("Couldn't load lyrics")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let lyrics = musicPlayer.lyrics {
                VStack(spacing: 0) {
                    // translation toggle — only show if original != english
                    if lyrics.originalLanguage != "en" {
                        HStack {
                            Spacer()
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    showingTranslation.toggle()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(showingTranslation ? "Original" : "Translate")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(showingTranslation ? .white : .white.opacity(0.45))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(showingTranslation ? .white.opacity(0.2) : .white.opacity(0.08))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 28)
                        .padding(.bottom, 12)
                    }

                    if lyrics.isSynced {
                        syncedLyrics(lyrics.lyricsJson)
                    } else {
                        plainLyrics(lyrics.plainText)
                    }
                }
            } else {
                Text("No lyrics available")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func displayText(for line: LyricLine) -> String {
        showingTranslation ? line.e : line.o
    }

    private func syncedLyrics(_ lines: [LyricLine]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 20) {
                    Color.clear.frame(height: 20)

                    ForEach(Array(lines.enumerated()), id: \.element.id) { idx, line in
                        if line.e != "♪" {
                            Button {
                                musicPlayer.seekProgress(
                                    line.timeSeconds / max(musicPlayer.duration, 1)
                                )
                                userScrolling = false
                            } label: {
                                Text(displayText(for: line))
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundStyle(
                                        musicPlayer.currentLyricIndex == idx
                                            ? .white
                                        : Color(.black)
                                    )
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .animation(.easeInOut(duration: 0.25), value: musicPlayer.currentLyricIndex)
                            }
                            .buttonStyle(.plain)
                            .id(line.id)
                        }
                    }

                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal, 28)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { _ in
                        userScrolling = true
                        scrollResetTask?.cancel()
                        scrollResetTask = Task {
                            try? await Task.sleep(for: .seconds(4))
                            if !Task.isCancelled {
                                userScrolling = false
                            }
                        }
                    }
            )
            .onChange(of: musicPlayer.currentLyricIndex) { _, idx in
                guard !userScrolling else { return }
                guard idx < lines.count else { return }
                let lineId = lines[idx].id
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(lineId, anchor: .center)
                }
            }
            .onAppear {
                guard musicPlayer.currentLyricIndex < lines.count else { return }
                let lineId = lines[musicPlayer.currentLyricIndex].id
                proxy.scrollTo(lineId, anchor: .center) // no animation — instant snap
            }
        }
    }

    private func plainLyrics(_ text: String) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(text)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
        }
    }
}
