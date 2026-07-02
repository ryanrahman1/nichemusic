//
//  CreatePostMusicPickerView.swift
//  Niche Music
//

import Kingfisher
import SwiftUI

struct CreatePostMusicPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: CreatePostStore

    let nicheOnly: Bool

    @State private var query = ""
    @State private var nicheResults: [NicheTrackSearchResult] = []
    @State private var catalogResults: [AppleMusicSearchSong] = []
    @State private var isSearching = false
    @State private var isResolving = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LibrarySearchField(text: $query, placeholder: nicheOnly ? "Search songs" : "Search songs")
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                if isSearching || isResolving {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if nicheOnly {
                    nicheList
                } else {
                    combinedList
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red.opacity(0.85))
                        .padding()
                }
            }
            .background(Theme.backgroundColor.ignoresSafeArea())
            .navigationTitle("Add Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
            .onChange(of: query) { _, _ in
                scheduleSearch()
            }
        }
    }

    @ViewBuilder
    private var nicheList: some View {
        if nicheResults.isEmpty {
            emptyState("Search for songs to attach.")
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(nicheResults) { track in
                        Button {
                            store.music = .niche(track)
                            dismiss()
                        } label: {
                            musicRow(
                                title: track.name,
                                subtitle: track.primaryArtistName ?? track.owner?.username ?? "Niche",
                                artworkUrl: track.artworkUrl
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }

    @ViewBuilder
    private var combinedList: some View {
        if nicheResults.isEmpty && catalogResults.isEmpty {
            emptyState("Search for niche or Apple Music songs.")
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !nicheResults.isEmpty {
                        sectionHeader("Niche")
                        ForEach(nicheResults) { track in
                            Button {
                                store.music = .niche(track)
                                dismiss()
                            } label: {
                                musicRow(
                                    title: track.name,
                                    subtitle: track.primaryArtistName ?? track.owner?.username ?? "Niche",
                                    artworkUrl: track.artworkUrl
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !catalogResults.isEmpty {
                        sectionHeader("Apple Music")
                        ForEach(catalogResults) { song in
                            Button {
                                Task { await selectCatalogSong(song) }
                            } label: {
                                musicRow(
                                    title: song.title,
                                    subtitle: song.artistName,
                                    artworkUrl: song.artworkURL?.absoluteString
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isResolving)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.42))
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var catalogList: some View {
        if catalogResults.isEmpty {
            emptyState("Search Apple Music or niche catalog.")
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(catalogResults) { song in
                        Button {
                            Task { await selectCatalogSong(song) }
                        } label: {
                            musicRow(
                                title: song.title,
                                subtitle: song.artistName,
                                artworkUrl: song.artworkURL?.absoluteString
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isResolving)
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white.opacity(0.45))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 28)
    }

    private func musicRow(title: String, subtitle: String, artworkUrl: String?) -> some View {
        HStack(spacing: 12) {
            Group {
                if let artworkUrl, let url = URL(string: artworkUrl.replacingOccurrences(of: "{w}x{h}", with: "120x120")) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white.opacity(0.08)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            await performSearch()
        }
    }

    private func performSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            nicheResults = []
            catalogResults = []
            return
        }

        isSearching = true
        errorMessage = nil

        do {
            if nicheOnly {
                nicheResults = try await store.searchNicheTracks(query: trimmed)
            } else {
                async let niche = store.searchNicheTracks(query: trimmed)
                async let catalog = store.searchCatalogSongs(query: trimmed)
                nicheResults = try await niche
                catalogResults = try await catalog
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isSearching = false
    }

    private func selectCatalogSong(_ song: AppleMusicSearchSong) async {
        isResolving = true
        errorMessage = nil

        do {
            let internalId = try await store.resolveCatalogTrack(appleSourceId: song.id)
            store.music = .catalog(
                internalTrackId: internalId,
                appleSourceId: song.id,
                title: song.title,
                artistName: song.artistName,
                artworkUrl: song.artworkURL?.absoluteString
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isResolving = false
    }
}
