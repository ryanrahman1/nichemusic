//
//  EditPublishedTrackView.swift
//  Niche Music
//

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct EditPublishedTrackView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var musicStore: MusicStore
    @EnvironmentObject private var profileStore: ProfileStore

    let trackId: String

    @StateObject private var publishStore = PublishMusicStore()
    @State private var name = ""
    @State private var explicit = false
    @State private var bpmText = ""
    @State private var visibility: PublishVisibility = .public
    @State private var credits: [PublishCreditEntry] = []
    @State private var artworkPickerItem: PhotosPickerItem?
    @State private var artworkCropRequest: ArtworkCropRequest?
    @State private var pendingArtworkJPEG: Data?
    @State private var showMomentPicker = false
    @State private var pendingMomentURL: URL?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?
    @State private var didInitialLoad = false

    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()

            if isLoading {
                NicheProgress()
            } else {
                form
            }
        }
        .navigationTitle("Edit track")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await save() }
                }
                .fontWeight(.semibold)
                .disabled(isSaving || isDeleting)
            }
        }
        .overlay { PublishBusyOverlay(isVisible: isSaving || isDeleting) }
        .overlay(alignment: .top) {
            PublishUploadToastOverlay(center: publishStore.uploadToasts)
        }
        .alert("Delete track?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task { await deleteTrack() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the track from your profile, search, and discover. This is not the same as making it private.")
        }
        .task {
            guard !didInitialLoad else { return }
            didInitialLoad = true
            await load()
        }
        .onChange(of: artworkPickerItem) { _, item in
            Task {
                await ArtworkPickFlow.consume(
                    item,
                    setCropRequest: { artworkCropRequest = $0 },
                    onError: { errorMessage = $0 },
                    onJPEG: { jpeg in
                        artworkPickerItem = nil
                        pendingArtworkJPEG = jpeg
                    }
                )
            }
        }
        .artworkCropSheet(request: $artworkCropRequest) { jpeg in
            artworkPickerItem = nil
            pendingArtworkJPEG = jpeg
        }
        .fileImporter(
            isPresented: $showMomentPicker,
            allowedContentTypes: PublishMediaSupport.videoContentTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            pendingMomentURL = url
        }
    }

    private var form: some View {
        Form {
            Section("Track") {
                PublishTextFieldRow(title: "Name", text: $name, limit: 100)
                Toggle("Explicit", isOn: $explicit).tint(Theme.accentColor)
                PublishTextFieldRow(title: "BPM", text: $bpmText, placeholder: "Optional")
                Picker("Visibility", selection: $visibility) {
                    ForEach(PublishVisibility.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            }
            .listRowBackground(Color.white.opacity(0.06))

            Section("Artwork") {
                HStack(spacing: 14) {
                    PublishArtworkPreview(jpegData: pendingArtworkJPEG, remoteURL: nil, size: 72)
                    PhotosPicker(selection: $artworkPickerItem, matching: .images) {
                        Text("Change artwork")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.accentColor)
                    }
                }
            }
            .listRowBackground(Color.white.opacity(0.06))

            Section("Moment") {
                Button("Change moment") {
                    showMomentPicker = true
                }
                .foregroundStyle(Theme.accentColor)
            }
            .listRowBackground(Color.white.opacity(0.06))

            Section {
                NavigationLink {
                    PublishCreditsEditorView(credits: $credits) { saved in
                        Task { await saveCredits(saved) }
                    }
                } label: {
                    HStack {
                        Text("Credits")
                        Spacer()
                        Text("\(credits.count)")
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            } footer: {
                Text("Send the full credited artist list when saving.")
                    .foregroundStyle(.white.opacity(0.4))
            }
            .listRowBackground(Color.white.opacity(0.06))

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Text("Delete track")
                }
            }
            .listRowBackground(Color.white.opacity(0.06))

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red.opacity(0.9))
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
        }
        .publishFormStyle()
    }

    private func load() async {
        isLoading = true
        do {
            let payload = try await musicStore.fetchTrackDetail(id: trackId, force: true)
            name = payload.track.name
            explicit = payload.track.explicit
            bpmText = payload.track.bpm > 0 ? String(payload.track.bpm) : ""
            visibility = payload.track.visibility == .public ? .public : .private
            credits = payload.track.credits?.compactMap(PublishCreditEntry.from) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func saveCredits(_ saved: [PublishCreditEntry]) async {
        errorMessage = nil

        do {
            try await publishStore.updatePublishedTrackCredits(trackId: trackId, credits: saved)
            credits = saved
            _ = try? await musicStore.fetchTrackDetail(id: trackId, force: true)
            PublishHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
            PublishHaptics.error()
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        let bpm = Int(bpmText.trimmingCharacters(in: .whitespacesAndNewlines))

        do {
            try await publishStore.updatePublishedTrack(
                trackId: trackId,
                name: name,
                explicit: explicit,
                bpm: bpm.flatMap { $0 > 0 ? $0 : nil },
                visibility: visibility,
                credits: credits,
                artworkJPEG: pendingArtworkJPEG,
                momentURL: pendingMomentURL
            )
            _ = try? await musicStore.fetchTrackDetail(id: trackId, force: true)
            await profileStore.loadMyDiscography(filter: .all, force: true)
            PublishHaptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            PublishHaptics.error()
        }

        isSaving = false
    }

    private func deleteTrack() async {
        isDeleting = true
        errorMessage = nil

        do {
            try await publishStore.deletePublishedTrack(trackId: trackId)
            await profileStore.loadMyDiscography(filter: .all, force: true)
            PublishHaptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            PublishHaptics.error()
        }

        isDeleting = false
    }
}

struct EditPublishedReleaseView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profileStore: ProfileStore

    let releaseId: String
    let initialName: String
    let initialArtworkURL: String?

    @StateObject private var publishStore = PublishMusicStore()
    @State private var name: String
    @State private var visibility: PublishVisibility = .public
    @State private var artworkPickerItem: PhotosPickerItem?
    @State private var artworkCropRequest: ArtworkCropRequest?
    @State private var pendingArtworkJPEG: Data?
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    init(releaseId: String, initialName: String, initialArtworkURL: String?) {
        self.releaseId = releaseId
        self.initialName = initialName
        self.initialArtworkURL = initialArtworkURL
        _name = State(initialValue: initialName)
    }

    var body: some View {
        Form {
            Section("Release") {
                PublishTextFieldRow(title: "Name", text: $name, limit: 100)
                Picker("Visibility", selection: $visibility) {
                    ForEach(PublishVisibility.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            }
            .listRowBackground(Color.white.opacity(0.06))

            Section("Artwork") {
                HStack(spacing: 14) {
                    PublishArtworkPreview(
                        jpegData: pendingArtworkJPEG,
                        remoteURL: initialArtworkURL,
                        size: 88
                    )
                    PhotosPicker(selection: $artworkPickerItem, matching: .images) {
                        Text("Change artwork")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.accentColor)
                    }
                }
            }
            .listRowBackground(Color.white.opacity(0.06))

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Text("Delete release")
                }
            }
            .listRowBackground(Color.white.opacity(0.06))

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red.opacity(0.9))
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
        }
        .publishFormStyle()
        .navigationTitle("Edit release")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await save() }
                }
                .fontWeight(.semibold)
                .disabled(isSaving || isDeleting)
            }
        }
        .overlay { PublishBusyOverlay(isVisible: isSaving || isDeleting) }
        .overlay(alignment: .top) {
            PublishUploadToastOverlay(center: publishStore.uploadToasts)
        }
        .alert("Delete release?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task { await deleteRelease() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the release from your profile, search, and discover.")
        }
        .onChange(of: artworkPickerItem) { _, item in
            Task {
                await ArtworkPickFlow.consume(
                    item,
                    setCropRequest: { artworkCropRequest = $0 },
                    onError: { errorMessage = $0 },
                    onJPEG: { jpeg in
                        artworkPickerItem = nil
                        pendingArtworkJPEG = jpeg
                    }
                )
            }
        }
        .artworkCropSheet(request: $artworkCropRequest) { jpeg in
            artworkPickerItem = nil
            pendingArtworkJPEG = jpeg
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        do {
            _ = try await publishStore.updatePublishedRelease(
                releaseId: releaseId,
                name: name,
                visibility: visibility,
                artworkJPEG: pendingArtworkJPEG
            )
            await profileStore.loadMyDiscography(filter: .all, force: true)
            PublishHaptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            PublishHaptics.error()
        }

        isSaving = false
    }

    private func deleteRelease() async {
        isDeleting = true
        errorMessage = nil

        do {
            try await publishStore.deletePublishedRelease(releaseId: releaseId)
            await profileStore.loadMyDiscography(filter: .all, force: true)
            PublishHaptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            PublishHaptics.error()
        }

        isDeleting = false
    }
}
