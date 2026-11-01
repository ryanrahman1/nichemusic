//
//  CreatePlaylistView.swift
//  Niche Music
//

import PhotosUI
import SwiftUI

struct CreatePlaylistView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var playlistStore: PlaylistStore

    @State private var name = ""
    @State private var description = ""
    @State private var visibility: PlaylistVisibility = .public
    @State private var coverPickerItem: PhotosPickerItem?
    @State private var coverCropRequest: ArtworkCropRequest?
    @State private var pendingCoverData: Data?
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    let onCreated: (PlaylistSummary) -> Void

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    coverSection

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))

                        TextField("My playlist", text: $name)
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))

                        TextField("Optional", text: $description, axis: .vertical)
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .lineLimit(3...6)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Visibility")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))

                        Picker("Visibility", selection: $visibility) {
                            ForEach(PlaylistVisibility.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.red.opacity(0.85))
                    }
                }
                .padding(20)
            }
            .background(Theme.backgroundColor.ignoresSafeArea())
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Theme.backgroundColor, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        Task { await submit() }
                    }
                    .fontWeight(.semibold)
                    .disabled(isSubmitting || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
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
                    Text(pendingCoverData == nil ? "Add cover" : "Change cover")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accentColor)
                }

                if pendingCoverData != nil {
                    Text("Cover ready to upload")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var coverPreview: some View {
        if let pendingCoverData, let uiImage = UIImage(data: pendingCoverData) {
            Image(uiImage: uiImage)
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

    private func submit() async {
        isSubmitting = true
        errorMessage = nil

        do {
            let playlist = try await playlistStore.createPlaylist(
                name: name,
                description: description,
                visibility: visibility,
                coverJPEGData: pendingCoverData
            )
            onCreated(playlist)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubmitting = false
    }
}
