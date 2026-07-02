//
//  AuxBattleSongSearchView.swift
//  Niche Music
//

import Kingfisher
import SwiftUI

struct AuxBattleSongSearchView: View {
    @Environment(\.dismiss) private var dismiss

    let songSource: AuxSongSource
    let onSelect: (AuxSongPickSource) -> Void

    @State private var query = ""
    @State private var nicheResults: [NicheTrackSearchResult] = []
    @State private var catalogResults: [AppleMusicSearchSong] = []
    @State private var isSearching = false
    @State private var isResolving = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    private let api = APIClient.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LibrarySearchField(text: $query, placeholder: searchPlaceholder)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                if isSearching || isResolving {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if nicheResults.isEmpty && catalogResults.isEmpty {
                    emptyState
                } else {
                    resultsList
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red.opacity(0.85))
                        .padding()
                }
            }
            .background(AuxBattleBackground())
            .navigationTitle("Pick a song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
            .onChange(of: query) { _, _ in
                scheduleSearch()
            }
        }
    }

    private var searchPlaceholder: String {
        switch songSource {
        case .niche: return "Search Niche Music"
        case .apple: return "Search Apple Music"
        case .any: return "Search songs"
        }
    }

    private var emptyState: some View {
        Text(emptyMessage)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white.opacity(0.45))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 28)
    }

    private var emptyMessage: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 2 {
            return "Type at least 2 characters to search."
        }
        return "No songs found."
    }

    private var resultsList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if songSource != .apple, !nicheResults.isEmpty {
                    sectionHeader("Niche")
                    ForEach(nicheResults) { track in
                        Button {
                            AuxBattleHaptics.selection()
                            onSelect(.niche(track))
                            dismiss()
                        } label: {
                            songRow(
                                title: track.name,
                                subtitle: track.primaryArtistName ?? track.owner?.username ?? "Niche",
                                artworkUrl: track.artworkUrl
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if songSource != .niche, !catalogResults.isEmpty {
                    sectionHeader("Apple Music")
                    ForEach(catalogResults) { song in
                        Button {
                            Task { await selectCatalogSong(song) }
                        } label: {
                            songRow(
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.42))
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func songRow(title: String, subtitle: String, artworkUrl: String?) -> some View {
        HStack(spacing: 12) {
            Group {
                if let artworkUrl,
                   let url = URL(string: artworkUrl.replacingOccurrences(of: "{w}x{h}", with: "120x120")) {
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
            if songSource == .apple {
                nicheResults = []
                catalogResults = try await searchCatalogSongs(query: trimmed)
            } else if songSource == .niche {
                catalogResults = []
                nicheResults = try await searchNicheTracks(query: trimmed)
            } else {
                async let niche = searchNicheTracks(query: trimmed)
                async let catalog = searchCatalogSongs(query: trimmed)
                nicheResults = try await niche
                catalogResults = try await catalog
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isSearching = false
    }

    private func searchNicheTracks(query: String) async throws -> [NicheTrackSearchResult] {
        let response: NicheTrackSearchResponse = try await api.request(
            Endpoints.nicheTrackSearch,
            method: .get,
            query: ["q": query, "limit": "20"]
        )
        return response.tracks
    }

    private func searchCatalogSongs(query: String) async throws -> [AppleMusicSearchSong] {
        let response: AppleMusicSearchResponse = try await api.request(
            Endpoints.appleMusicSearch,
            method: .get,
            query: ["q": query, "types": "songs"]
        )
        return response.data.results?.songs?.data ?? []
    }

    private func selectCatalogSong(_ song: AppleMusicSearchSong) async {
        isResolving = true
        errorMessage = nil

        do {
            let detail: AppleSongDetailResponse = try await api.request(
                Endpoints.appleMusicSong(id: song.id),
                method: .get
            )
            AuxBattleHaptics.selection()
            onSelect(.apple(
                trackId: detail.track.id,
                appleSourceId: song.id,
                name: detail.track.name,
                artistName: detail.track.artistName ?? song.artistName,
                artworkUrl: detail.track.artworkUrl,
                previewUrl: detail.track.previewUrl,
                durationMs: 30_000
            ))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isResolving = false
    }
}
