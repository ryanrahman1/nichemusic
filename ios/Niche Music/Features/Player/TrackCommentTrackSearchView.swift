//
//  TrackCommentTrackSearchView.swift
//  Niche Music
//

import SwiftUI
import Kingfisher

struct TrackCommentTrackSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var commentsStore: TrackCommentsStore

    let trackId: String
    let parentCommentId: String?
    let replyToCommentId: String?

    @State private var query = ""
    @State private var results: [AppleMusicSearchSong] = []
    @State private var isSearching = false
    @State private var isPosting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Search songs...", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))

                if isPosting {
                    VStack(spacing: 12) {
                        Spacer()
                        ProgressView()
                        Text("Posting track...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else if isSearching {
                    VStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if results.isEmpty {
                    VStack(spacing: 10) {
                        Spacer()
                        Image(systemName: "music.note.list")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary.opacity(0.5))
                        Text(query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
                             ? "No songs found"
                             : "Search for a song to share")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    List(results) { song in
                        Button {
                            Task { await selectSong(song) }
                        } label: {
                            HStack(spacing: 12) {
                                if let artworkURL = song.artworkURL {
                                    KFImage(artworkURL)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 46, height: 46)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.primary.opacity(0.08))
                                        .frame(width: 46, height: 46)
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(song.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(song.artistName)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .padding()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .navigationTitle("Share a Track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onChange(of: query) { _, newValue in
            Task { await search(query: newValue) }
        }
    }

    private func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            results = try await commentsStore.searchAppleSongs(query: trimmed)
        } catch {
            results = []
            errorMessage = error.localizedDescription
        }
    }

    private func selectSong(_ song: AppleMusicSearchSong) async {
        isPosting = true
        errorMessage = nil

        do {
            try await commentsStore.sendTrackComment(
                trackId: trackId,
                appleSongId: song.id,
                parentCommentId: parentCommentId,
                replyToCommentId: replyToCommentId
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isPosting = false
        }
    }
}
