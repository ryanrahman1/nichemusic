//
//  EditPlaylistView.swift
//  Niche Music
//

import Kingfisher
import PhotosUI
import SwiftUI

struct EditPlaylistView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var playlistStore: PlaylistStore

    let playlist: PlaylistDetail

    @State private var name: String
    @State private var description: String
    @State private var visibility: PlaylistVisibility
    @State private var orderedItems: [PlaylistItem]
    @State private var coverPickerItem: PhotosPickerItem?
    @State private var coverCropRequest: ArtworkCropRequest?
    @State private var pendingCoverData: Data?
    @State private var isSubmitting = false
    @State private var isLoadingTracks = false
    @State private var movingItemIds: Set<String> = []
    @State private var errorMessage: String?

    init(playlist: PlaylistDetail) {
        self.playlist = playlist
        _name = State(initialValue: playlist.name)
        _description = State(initialValue: playlist.description ?? "")
        _visibility = State(initialValue: playlist.visibility)
        _orderedItems = State(
            initialValue: playlist.items.sorted { $0.sortKey < $1.sortKey }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    coverSection
                }
                .listRowBackground(Color.white.opacity(0.06))

                Section {
                    TextField("Playlist name", text: $name)
                        .foregroundStyle(.white)

                    TextField("Description", text: $description, axis: .vertical)
                        .foregroundStyle(.white)
                        .lineLimit(3...6)
                } header: {
                    Text("Details")
                }
                .listRowBackground(Color.white.opacity(0.06))

                Section {
                    Picker("Visibility", selection: $visibility) {
                        ForEach(PlaylistVisibility.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("Visibility")
                }
                .listRowBackground(Color.white.opacity(0.06))

                Section {
                    if isLoadingTracks {
                        HStack {
                            Spacer()
                            ProgressView()
                                .tint(.white)
                            Spacer()
                        }
                        .listRowBackground(Color.white.opacity(0.06))
                    } else if orderedItems.isEmpty {
                        Text("No tracks in this playlist yet.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .listRowBackground(Color.white.opacity(0.06))
                    } else {
                        ForEach(orderedItems) { item in
                            reorderRow(for: item)
                                .listRowBackground(Color.white.opacity(0.06))
                                .moveDisabled(movingItemIds.contains(item.id))
                        }
                        .onMove(perform: moveTracks)
                    }
                } header: {
                    Text("Tracks")
                } footer: {
                    if !orderedItems.isEmpty {
                        Text("Drag tracks to reorder.")
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.red.opacity(0.85))
                            .listRowBackground(Color.white.opacity(0.06))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundColor.ignoresSafeArea())
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Theme.backgroundColor, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task { await submit() }
                    }
                    .fontWeight(.semibold)
                    .disabled(isSubmitting || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                await loadTracks()
            }
            .onChange(of: coverPickerItem) { _, item in
                Task {
                    await ArtworkPickFlow.consume(
                        item,
                        setCropRequest: { coverCropRequest = $0 },
                        onError: { errorMessage = $0 },
                        onJPEG: { jpeg in
                            coverPickerItem = nil
                            pendingCoverData = jpeg
                            errorMessage = nil
                        }
                    )
                }
            }
            .artworkCropSheet(request: $coverCropRequest) { jpeg in
                coverPickerItem = nil
                pendingCoverData = jpeg
                errorMessage = nil
            }
        }
    }

    private var coverSection: some View {
        HStack(spacing: 16) {
            coverPreview
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                PhotosPicker(selection: $coverPickerItem, matching: .images) {
                    Text("Change cover")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accentColor)
                }

                if pendingCoverData != nil {
                    Text("New cover ready to upload")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func reorderRow(for item: PlaylistItem) -> some View {
        HStack(spacing: 12) {
            trackArtwork(for: item)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.track?.name ?? "Unavailable track")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                if let artistName = item.track?.primaryArtistName {
                    Text(artistName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if movingItemIds.contains(item.id) {
                ProgressView()
                    .tint(.white)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func trackArtwork(for item: PlaylistItem) -> some View {
        if let artworkUrl = item.track?.artworkUrl, let url = URL(string: artworkUrl) {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.white.opacity(0.28))
                }
        }
    }

    @ViewBuilder
    private var coverPreview: some View {
        if let pendingCoverData, let uiImage = UIImage(data: pendingCoverData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else if let imageUrl = playlist.imageUrl, let url = URL(string: imageUrl) {
            KFImage(url)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
        }
    }

    private func loadTracks() async {
        isLoadingTracks = true
        await playlistStore.loadAllPlaylistItems(id: playlist.id)
        syncOrderedItemsFromStore()
        isLoadingTracks = false
    }

    private func syncOrderedItemsFromStore() {
        guard let detail = playlistStore.detailsById[playlist.id] else { return }
        orderedItems = detail.items.sorted { $0.sortKey < $1.sortKey }
    }

    private func moveTracks(from source: IndexSet, to destination: Int) {
        var reordered = orderedItems
        reordered.move(fromOffsets: source, toOffset: destination)

        guard let fromIndex = source.first else { return }
        let movedItem = orderedItems[fromIndex]
        guard let newIndex = reordered.firstIndex(where: { $0.id == movedItem.id }) else { return }

        let afterSortKey = newIndex > 0 ? reordered[newIndex - 1].sortKey : nil
        let beforeSortKey = newIndex < reordered.count - 1 ? reordered[newIndex + 1].sortKey : nil
        let previousOrder = orderedItems

        orderedItems = reordered
        movingItemIds.insert(movedItem.id)
        errorMessage = nil

        Task {
            do {
                try await playlistStore.moveItem(
                    playlistId: playlist.id,
                    itemId: movedItem.id,
                    afterSortKey: afterSortKey,
                    beforeSortKey: beforeSortKey,
                    orderedItemIds: reordered.map(\.id)
                )
                syncOrderedItemsFromStore()
            } catch {
                orderedItems = previousOrder
                errorMessage = error.localizedDescription
            }

            movingItemIds.remove(movedItem.id)
        }
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil

        do {
            _ = try await playlistStore.updatePlaylist(
                id: playlist.id,
                name: name,
                description: description,
                visibility: visibility,
                coverJPEGData: pendingCoverData
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubmitting = false
    }
}
