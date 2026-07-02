//
//  PlaylistAddTrackSearchView.swift
//  Niche Music
//

import Kingfisher
import SwiftUI

struct PlaylistAddTrackSearchView: View {
    let playlistId: String

    @EnvironmentObject private var playlistStore: PlaylistStore

    @State private var query = ""
    @State private var results: [NicheTrackSearchResult] = []
    @State private var isSearching = false
    @State private var addingTrackIds: Set<String> = []
    @State private var addedTrackIds: Set<String> = []
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            LibrarySearchField(text: $query, placeholder: "Search niche tracks")
                .padding(.top, 8)
                .padding(.bottom, 12)

            if isSearching {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { track in
                            trackRow(track)
                        }
                    }
                    .padding(.bottom, 120)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red.opacity(0.85))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .background(Theme.backgroundColor.ignoresSafeArea())
        .navigationTitle("Add Tracks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Theme.backgroundColor, for: .navigationBar)
        .onAppear {
            seedAddedTrackIds()
        }
        .onChange(of: query) { _, _ in
            scheduleSearch()
        }
    }

    private var emptyMessage: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Search for niche tracks to add to this playlist."
        }
        if trimmed.count < 2 {
            return "Type at least 2 characters to search."
        }
        return "No tracks found for \"\(trimmed)\"."
    }

    @ViewBuilder
    private func trackRow(_ track: NicheTrackSearchResult) -> some View {
        let isAdded = isTrackInPlaylist(track.id) || addedTrackIds.contains(track.id)
        let isAdding = addingTrackIds.contains(track.id)

        HStack(spacing: 12) {
            artwork(for: track)

            VStack(alignment: .leading, spacing: 4) {
                Text(track.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                if let artistName = track.primaryArtistName {
                    Text(artistName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button {
                Task { await addTrack(track) }
            } label: {
                Group {
                    if isAdding {
                        ProgressView()
                            .tint(.white)
                    } else if isAdded {
                        Label("Added", systemImage: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.accentColor)
                    } else {
                        Text("Add")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Theme.accentColor.opacity(0.9), in: Capsule())
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isAdded || isAdding)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func artwork(for track: NicheTrackSearchResult) -> some View {
        if let artworkUrl = track.artworkUrl, let url = URL(string: artworkUrl) {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.white.opacity(0.28))
                }
        }
    }

    private func seedAddedTrackIds() {
        guard let detail = playlistStore.detailsById[playlistId] else { return }
        addedTrackIds = Set(detail.items.map(\.nicheTrackId))
    }

    private func isTrackInPlaylist(_ trackId: String) -> Bool {
        playlistStore.detailsById[playlistId]?.items.contains {
            $0.nicheTrackId == trackId || $0.track?.id == trackId
        } ?? false
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await performSearch()
        }
    }

    private func performSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            return
        }

        isSearching = true
        errorMessage = nil

        do {
            results = try await playlistStore.searchNicheTracks(query: trimmed)
        } catch {
            results = []
            errorMessage = error.localizedDescription
        }

        isSearching = false
    }

    private func addTrack(_ track: NicheTrackSearchResult) async {
        guard !addingTrackIds.contains(track.id), !isTrackInPlaylist(track.id) else { return }

        addingTrackIds.insert(track.id)
        errorMessage = nil

        do {
            try await playlistStore.addTrack(playlistId: playlistId, trackId: track.id)
            addedTrackIds.insert(track.id)
        } catch {
            errorMessage = error.localizedDescription
        }

        addingTrackIds.remove(track.id)
    }
}
