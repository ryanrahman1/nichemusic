//
//  PublishTrackEditorView.swift
//  Niche Music
//

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct PublishTrackEditorView: View {
    @ObservedObject var store: PublishMusicStore
    let trackId: String
    let context: Context

    enum Context {
        case single
        case releaseTrack(releaseArtworkJPEG: Data?, releaseArtworkURL: String?)
    }

    @State private var artworkPickerItem: PhotosPickerItem?
    @State private var artworkCropRequest: ArtworkCropRequest?
    @State private var momentPickerItem: PhotosPickerItem?
    @State private var momentThumbnail: UIImage?
    @State private var localCredits: [PublishCreditEntry] = []
    @State private var showAudioReplacePicker = false
    @FocusState private var focusedField: PublishKeyboardFocus?

    private var track: PublishTrackDraft {
        if case .single(let draft) = store.flow, draft.id == trackId {
            return draft
        }
        if case .release(let draft) = store.flow,
           let match = draft.tracks.first(where: { $0.id == trackId }) {
            return match
        }
        return PublishTrackDraft(id: trackId)
    }

    var body: some View {
        Form {
            Section("Audio") {
                PublishAudioFileRow(
                    fileName: track.audioFileLabel ?? (track.audioUpload.isUploaded ? "Uploaded audio" : "Audio file"),
                    state: track.audioUpload
                )
                if case .single = context {
                    Button("Replace audio file") {
                        showAudioReplacePicker = true
                        PublishHaptics.tap()
                    }
                    .buttonStyle(.borderless)
                }
                if let durationMs = track.durationMs {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(PublishMediaSupport.formattedDuration(ms: durationMs))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
            .listRowBackground(Color.white.opacity(0.06))

            Section("Track details") {
                PublishTextFieldRow(
                    title: "Track name",
                    text: nameBinding,
                    placeholder: "Track name",
                    limit: 100,
                    focus: $focusedField,
                    focusValue: .trackName
                )

                DatePicker("Release date", selection: releaseDateBinding, displayedComponents: .date)
                    .tint(Theme.accentColor)

                Picker("Visibility", selection: visibilityBinding) {
                    ForEach(PublishVisibility.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }

                Toggle("Explicit", isOn: explicitBinding)
                    .tint(Theme.accentColor)

                PublishTextFieldRow(
                    title: "BPM",
                    text: bpmBinding,
                    placeholder: "Optional",
                    focus: $focusedField,
                    focusValue: .bpm
                )
            }
            .listRowBackground(Color.white.opacity(0.06))

            artworkSection
            momentSection

            Section {
                NavigationLink {
                    PublishCreditsEditorView(credits: $localCredits) { saved in
                        Task { await saveCredits(saved) }
                    }
                } label: {
                    HStack {
                        Text("Credits")
                        Spacer()
                        Text("\(localCredits.count)")
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
            .listRowBackground(Color.white.opacity(0.06))

            if let errorMessage = store.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.system(size: 14))
                        .foregroundStyle(.red.opacity(0.9))
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
        }
        .publishFormStyle()
        .publishDismissKeyboardOnTap(focus: $focusedField)
        .publishKeyboardToolbar(focus: $focusedField)
        .navigationTitle(contextTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            localCredits = track.credits
        }
        .onChange(of: track.credits) { _, value in
            localCredits = value
        }
        .onChange(of: artworkPickerItem) { _, item in
            Task {
                await ArtworkPickFlow.consume(
                    item,
                    setCropRequest: { artworkCropRequest = $0 },
                    onError: { store.errorMessage = $0 },
                    onJPEG: { jpeg in
                        artworkPickerItem = nil
                        await uploadArtwork(jpeg)
                    }
                )
            }
        }
        .artworkCropSheet(request: $artworkCropRequest) { jpeg in
            artworkPickerItem = nil
            Task { await uploadArtwork(jpeg) }
        }
        .onChange(of: momentPickerItem) { _, item in
            Task { await loadMoment(from: item) }
        }
        .onChange(of: track.pendingMomentURL) { _, url in
            Task { await refreshMomentThumbnail(from: url) }
        }
        .task(id: track.pendingMomentURL) {
            await refreshMomentThumbnail(from: track.pendingMomentURL)
        }
        .onChange(of: nameBinding.wrappedValue) { _, _ in scheduleSync() }
        .onChange(of: releaseDateBinding.wrappedValue) { _, _ in scheduleSync() }
        .onChange(of: visibilityBinding.wrappedValue) { _, _ in scheduleSync() }
        .onChange(of: explicitBinding.wrappedValue) { _, _ in scheduleSync() }
        .onChange(of: bpmBinding.wrappedValue) { _, _ in scheduleSync() }
        .fileImporter(
            isPresented: $showAudioReplacePicker,
            allowedContentTypes: PublishMediaSupport.audioContentTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                await store.replaceSingleDraftAudio(with: url)
            }
        }
    }

    private var contextTitle: String {
        switch context {
        case .single: "Single"
        case .releaseTrack: "Track \(track.trackNumber)"
        }
    }

    @ViewBuilder
    private var artworkSection: some View {
        Section {
            PublishFullWidthArtworkPreview(
                jpegData: displayArtworkJPEG,
                remoteURL: displayArtworkURL
            )
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            .listRowSeparator(.hidden, edges: .bottom)
        } header: {
            Text("Artwork")
        }
        .listRowBackground(Color.white.opacity(0.06))

        Section {
            if usesReleaseArtwork {
                Text("Using release artwork")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
            }

            PublishFormPickerRow(
                title: track.hasCustomArtwork ? "Change artwork" : "Choose artwork from library",
                selection: $artworkPickerItem,
                matching: .images
            )

            if track.hasCustomArtwork, case .releaseTrack = context {
                Button("Use release artwork") {
                    clearCustomArtwork()
                }
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.72))
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            PublishUploadStatusRow(title: "Artwork upload", state: track.artworkUpload)
        }
        .listRowBackground(Color.white.opacity(0.06))
    }

    @ViewBuilder
    private var momentSection: some View {
        Section {
            PublishFullWidthMomentPreview(
                thumbnail: momentThumbnail,
                uploadState: track.momentUpload,
                fileLabel: track.pendingMomentURL?.lastPathComponent
            )
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            .listRowSeparator(.hidden, edges: .bottom)
        } header: {
            Text("Moment")
        }
        .listRowBackground(Color.white.opacity(0.06))

        Section {
            PublishFormPickerRow(
                title: "Choose moment from library",
                selection: $momentPickerItem,
                matching: .videos
            )
        }
        .listRowBackground(Color.white.opacity(0.06))
    }

    private var usesReleaseArtwork: Bool {
        if case .releaseTrack = context {
            return !track.hasCustomArtwork
        }
        return false
    }

    private var displayArtworkJPEG: Data? {
        if track.hasCustomArtwork {
            return track.pendingArtworkJPEG
        }
        if case .releaseTrack(let releaseJPEG, _) = context {
            return releaseJPEG
        }
        return track.pendingArtworkJPEG
    }

    private var displayArtworkURL: String? {
        if track.hasCustomArtwork {
            return track.artworkURL
        }
        if case .releaseTrack(_, let releaseURL) = context {
            return releaseURL
        }
        return track.artworkURL
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { track.name },
            set: { newValue in mutateTrack { $0.name = newValue } }
        )
    }

    private var releaseDateBinding: Binding<Date> {
        Binding(
            get: { track.releaseDate },
            set: { newValue in mutateTrack { $0.releaseDate = newValue } }
        )
    }

    private var visibilityBinding: Binding<PublishVisibility> {
        Binding(
            get: { track.visibility },
            set: { newValue in mutateTrack { $0.visibility = newValue } }
        )
    }

    private var explicitBinding: Binding<Bool> {
        Binding(
            get: { track.explicit },
            set: { newValue in mutateTrack { $0.explicit = newValue } }
        )
    }

    private var bpmBinding: Binding<String> {
        Binding(
            get: { track.bpmText },
            set: { newValue in mutateTrack { $0.bpmText = newValue } }
        )
    }

    private func mutateTrack(_ mutate: (inout PublishTrackDraft) -> Void) {
        switch context {
        case .single:
            store.updateSingleTrack(mutate)
        case .releaseTrack:
            store.updateReleaseTrack(id: track.id, mutate)
        }
    }

    private func scheduleSync() {
        switch context {
        case .single:
            store.scheduleSingleMetadataSync()
        case .releaseTrack:
            store.scheduleReleaseTrackMetadataSync(trackId: track.id)
        }
    }

    private func uploadArtwork(_ jpeg: Data) async {
        switch context {
        case .single:
            await store.uploadSingleArtwork(jpegData: jpeg)
        case .releaseTrack:
            await store.uploadReleaseTrackArtwork(trackId: track.id, jpegData: jpeg)
        }
    }

    private func loadMoment(from item: PhotosPickerItem?) async {
        guard let item else { return }

        guard let picked = try? await item.loadTransferable(type: PickedVideoTransferable.self) else {
            store.errorMessage = "Couldn't use that video."
            return
        }

        await uploadMoment(from: picked.url)
    }

    private func refreshMomentThumbnail(from url: URL?) async {
        guard let url else {
            momentThumbnail = nil
            return
        }
        momentThumbnail = await PublishMediaSupport.videoThumbnail(for: url)
    }

    private func uploadMoment(from url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        switch context {
        case .single:
            await store.uploadSingleMoment(from: url)
        case .releaseTrack:
            await store.uploadReleaseTrackMoment(trackId: track.id, from: url)
        }
    }

    private func clearCustomArtwork() {
        store.clearReleaseTrackArtwork(trackId: track.id)
    }

    private func saveCredits(_ credits: [PublishCreditEntry]) async {
        switch context {
        case .single:
            await store.updateSingleCredits(credits)
        case .releaseTrack:
            await store.updateReleaseTrackCredits(trackId: track.id, credits: credits)
        }
    }
}

struct PublishSingleTrackView: View {
    @ObservedObject var store: PublishMusicStore

    private var draft: PublishTrackDraft {
        if case .single(let draft) = store.flow { return draft }
        return PublishTrackDraft(id: "")
    }

    private var canReview: Bool {
        draft.isReadyToPublish
    }

    var body: some View {
        PublishTrackEditorView(store: store, trackId: draft.id, context: .single)
            .safeAreaInset(edge: .bottom) {
                PublishBottomActionBar(title: "Review", isEnabled: canReview) {
                    store.showSingleReview()
                    PublishHaptics.tap()
                }
            }
            .overlay { PublishBusyOverlay(isVisible: store.isBusy) }
    }
}

struct PublishReleaseEditorView: View {
    @ObservedObject var store: PublishMusicStore
    let onAddTrack: () -> Void

    @State private var artworkPickerItem: PhotosPickerItem?
    @State private var artworkCropRequest: ArtworkCropRequest?
    @State private var editMode: EditMode = .inactive
    @FocusState private var focusedField: PublishKeyboardFocus?

    private var draft: PublishReleaseDraft {
        if case .release(let draft) = store.flow { return draft }
        return PublishReleaseDraft(id: "", releaseType: .ep)
    }

    private var canReview: Bool {
        draft.isReadyToPublish
    }

    var body: some View {
        Form {
            Section("Release") {
                PublishTextFieldRow(
                    title: "Release name",
                    text: releaseNameBinding,
                    placeholder: "Release name",
                    limit: 100,
                    focus: $focusedField,
                    focusValue: .releaseName
                )

                Picker("Type", selection: releaseTypeBinding) {
                    ForEach(PublishReleaseType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }

                DatePicker("Release date", selection: releaseDateBinding, displayedComponents: .date)
                    .tint(Theme.accentColor)

                Picker("Visibility", selection: releaseVisibilityBinding) {
                    ForEach(PublishVisibility.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            }
            .listRowBackground(Color.white.opacity(0.06))

            Section("Artwork") {
                PublishFullWidthArtworkPreview(
                    jpegData: draft.pendingArtworkJPEG,
                    remoteURL: draft.artworkURL
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowSeparator(.hidden, edges: .bottom)
            }
            .listRowBackground(Color.white.opacity(0.06))

            Section {
                PublishFormPickerRow(
                    title: "Choose artwork from library",
                    selection: $artworkPickerItem,
                    matching: .images
                )

                PublishUploadStatusRow(title: "Artwork upload", state: draft.artworkUpload)
            }
            .listRowBackground(Color.white.opacity(0.06))

            Section {
                ForEach(draft.tracks) { track in
                    NavigationLink {
                        PublishTrackEditorView(
                            store: store,
                            trackId: track.id,
                            context: .releaseTrack(
                                releaseArtworkJPEG: draft.pendingArtworkJPEG,
                                releaseArtworkURL: draft.artworkURL
                            )
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Text("\(track.trackNumber)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white.opacity(0.45))
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.name.isEmpty ? "Untitled track" : track.name)
                                    .foregroundStyle(.white)
                                Text(track.audioUpload.statusLabel)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(track.audioUpload.isUploaded ? .green : .white.opacity(0.42))
                            }
                        }
                    }
                }
                .onMove(perform: moveTracks)
                .onDelete(perform: deleteTracks)

                Button(action: onAddTrack) {
                    Label("Add track", systemImage: "plus.circle.fill")
                        .foregroundStyle(Theme.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            } header: {
                HStack {
                    Text("Tracklist")
                    Spacer()
                    EditButton()
                        .foregroundStyle(Theme.accentColor)
                }
            } footer: {
                Text("Track numbers update automatically when you reorder.")
                    .foregroundStyle(.white.opacity(0.4))
            }
            .listRowBackground(Color.white.opacity(0.06))

            if let errorMessage = store.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.system(size: 14))
                        .foregroundStyle(.red.opacity(0.9))
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
        }
        .publishFormStyle()
        .publishDismissKeyboardOnTap(focus: $focusedField)
        .publishKeyboardToolbar(focus: $focusedField)
        .environment(\.editMode, $editMode)
        .navigationTitle(draft.releaseType.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            PublishBottomActionBar(title: "Review release", isEnabled: canReview) {
                store.showReleaseReview()
                PublishHaptics.tap()
            }
        }
        .overlay { PublishBusyOverlay(isVisible: store.isBusy) }
        .onChange(of: artworkPickerItem) { _, item in
            Task {
                await ArtworkPickFlow.consume(
                    item,
                    setCropRequest: { artworkCropRequest = $0 },
                    onError: { store.errorMessage = $0 },
                    onJPEG: { jpeg in
                        artworkPickerItem = nil
                        await store.uploadReleaseArtwork(jpegData: jpeg)
                    }
                )
            }
        }
        .artworkCropSheet(request: $artworkCropRequest) { jpeg in
            artworkPickerItem = nil
            Task { await store.uploadReleaseArtwork(jpegData: jpeg) }
        }
        .onChange(of: releaseNameBinding.wrappedValue) { _, _ in store.scheduleReleaseMetadataSync() }
        .onChange(of: releaseTypeBinding.wrappedValue) { _, _ in store.scheduleReleaseMetadataSync() }
        .onChange(of: releaseDateBinding.wrappedValue) { _, _ in
            store.scheduleReleaseMetadataSync()
            for track in draft.tracks {
                store.updateReleaseTrack(id: track.id) { $0.releaseDate = releaseDateBinding.wrappedValue }
                store.scheduleReleaseTrackMetadataSync(trackId: track.id)
            }
        }
        .onChange(of: releaseVisibilityBinding.wrappedValue) { _, _ in store.scheduleReleaseMetadataSync() }
    }

    private var releaseNameBinding: Binding<String> {
        Binding(
            get: { draft.name },
            set: { newValue in store.updateRelease { $0.name = newValue } }
        )
    }

    private var releaseTypeBinding: Binding<PublishReleaseType> {
        Binding(
            get: { draft.releaseType },
            set: { newValue in store.updateRelease { $0.releaseType = newValue } }
        )
    }

    private var releaseDateBinding: Binding<Date> {
        Binding(
            get: { draft.releaseDate },
            set: { newValue in store.updateRelease { $0.releaseDate = newValue } }
        )
    }

    private var releaseVisibilityBinding: Binding<PublishVisibility> {
        Binding(
            get: { draft.visibility },
            set: { newValue in store.updateRelease { $0.visibility = newValue } }
        )
    }

    private func moveTracks(from source: IndexSet, to destination: Int) {
        store.moveReleaseTracks(from: source, to: destination)
        PublishHaptics.selection()
    }

    private func deleteTracks(at offsets: IndexSet) {
        for index in offsets {
            let track = draft.tracks[index]
            store.removeReleaseTrack(id: track.id)
        }
    }
}
