//
//  PublishMusicFlowView.swift
//  Niche Music
//

import SwiftUI
import UniformTypeIdentifiers

struct PublishMusicFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profileStore: ProfileStore

    let onPublished: (PublishMusicDestination) -> Void

    @StateObject private var store = PublishMusicStore()
    @State private var isAudioImporterPresented = false
    @State private var audioImportTarget: AudioImportTarget = .single

    private enum AudioImportTarget {
        case single
        case releaseTrack
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundColor.ignoresSafeArea()
                destinationView
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .overlay(alignment: .top) {
                PublishUploadToastOverlay(center: store.uploadToasts)
            }
            .fileImporter(
                isPresented: $isAudioImporterPresented,
                allowedContentTypes: PublishMediaSupport.audioContentTypes,
                allowsMultipleSelection: false
            ) { result in
                let target = audioImportTarget
                guard case .success(let urls) = result, let url = urls.first else { return }
                Task {
                    switch target {
                    case .single:
                        await beginSingle(from: url)
                    case .releaseTrack:
                        await beginReleaseTrack(from: url)
                    }
                }
            }
        }
    }

    private func presentAudioImporter(for target: AudioImportTarget) {
        audioImportTarget = target
        isAudioImporterPresented = true
    }

    @ViewBuilder
    private var destinationView: some View {
        switch store.flow {
        case .choosingType:
            PublishTypePickerView(
                store: store,
                onSingle: {
                    presentAudioImporter(for: .single)
                    PublishHaptics.tap()
                },
                onRelease: { type in
                    Task { await store.beginRelease(type: type) }
                }
            )
            .task {
                await store.refreshSavedDrafts()
            }

        case .single:
            PublishSingleTrackView(store: store)

        case .release:
            PublishReleaseEditorView(store: store) {
                presentAudioImporter(for: .releaseTrack)
                PublishHaptics.tap()
            }

        case .reviewSingle:
            PublishSingleReviewView(store: store) { destination in
                Task {
                    await profileStore.loadMyDiscography(filter: .all, force: true)
                    onPublished(destination)
                }
            }

        case .reviewRelease:
            PublishReleaseReviewView(store: store) { destination in
                Task {
                    await profileStore.loadMyDiscography(filter: .all, force: true)
                    onPublished(destination)
                }
            }
        }
    }

    private var navigationTitle: String {
        switch store.flow {
        case .choosingType: "Publish"
        case .single: "New single"
        case .release(let draft): "New \(draft.releaseType.label.lowercased())"
        case .reviewSingle: "Review"
        case .reviewRelease: "Review"
        }
    }

    private func beginSingle(from url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        await store.beginSingle(with: url)
    }

    private func beginReleaseTrack(from url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        await store.addReleaseTrack(from: url)
    }
}

struct PublishTypePickerView: View {
    @ObservedObject var store: PublishMusicStore
    let onSingle: () -> Void
    let onRelease: (PublishReleaseType) -> Void

    @State private var draftPendingDeletion: DraftDeletionTarget?

    private enum DraftDeletionTarget: Identifiable {
        case single(String)
        case release(String)

        var id: String {
            switch self {
            case .single(let id), .release(let id): id
            }
        }
    }

    var body: some View {
        Form {
            if !store.singleDraftSummaries.isEmpty || !store.releaseDraftSummaries.isEmpty {
                savedDraftsSection
            }

            Section {
                Button(action: onSingle) {
                    HStack(spacing: 14) {
                        Image(systemName: "music.note")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.accentColor)
                            .frame(width: 34)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Single track")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("Publish one song directly.")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(Color.white.opacity(0.06))

            Section("EP / Album") {
                ForEach(PublishReleaseType.allCases) { type in
                    Button {
                        onRelease(type)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: type == .album ? "square.stack.fill" : "rectangle.stack.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Theme.accentColor)
                                .frame(width: 34)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(type.label)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("Release multiple tracks together.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
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
        .overlay { PublishBusyOverlay(isVisible: store.isBusy || store.isLoadingDrafts) }
        .confirmationDialog(
            "Delete this draft?",
            isPresented: Binding(
                get: { draftPendingDeletion != nil },
                set: { if !$0 { draftPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete draft", role: .destructive) {
                guard let target = draftPendingDeletion else { return }
                draftPendingDeletion = nil
                Task {
                    switch target {
                    case .single(let id):
                        _ = await store.deleteSingleDraft(id: id)
                    case .release(let id):
                        _ = await store.deleteReleaseDraft(id: id)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                draftPendingDeletion = nil
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    @ViewBuilder
    private var savedDraftsSection: some View {
        if !store.singleDraftSummaries.isEmpty {
            Section("Saved singles") {
                ForEach(store.singleDraftSummaries) { draft in
                    Button {
                        Task { await store.resumeSingleDraft(id: draft.id) }
                        PublishHaptics.tap()
                    } label: {
                        PublishDraftSummaryRow(
                            title: draft.name?.isEmpty == false ? draft.name! : "Untitled single",
                            subtitle: singleDraftSubtitle(draft),
                            artworkURL: draft.artworkUrl
                        )
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            draftPendingDeletion = .single(draft.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listRowBackground(Color.white.opacity(0.06))
        }

        if !store.releaseDraftSummaries.isEmpty {
            Section("Saved releases") {
                ForEach(store.releaseDraftSummaries) { draft in
                    Button {
                        Task { await store.resumeReleaseDraft(id: draft.id) }
                        PublishHaptics.tap()
                    } label: {
                        PublishDraftSummaryRow(
                            title: draft.name?.isEmpty == false ? draft.name! : "Untitled \(draft.releaseType)",
                            subtitle: releaseDraftSubtitle(draft),
                            artworkURL: draft.artworkUrl
                        )
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            draftPendingDeletion = .release(draft.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listRowBackground(Color.white.opacity(0.06))
        }
    }

    private func singleDraftSubtitle(_ draft: PublishTrackDraftSummary) -> String {
        var parts: [String] = [draft.releaseDate]
        if let durationMs = draft.durationMs {
            parts.append(PublishMediaSupport.formattedDuration(ms: durationMs))
        }
        return parts.joined(separator: " · ")
    }

    private func releaseDraftSubtitle(_ draft: PublishReleaseDraftSummary) -> String {
        let typeLabel = PublishReleaseType(rawValue: draft.releaseType)?.label ?? draft.releaseType.capitalized
        return "\(typeLabel) · \(draft.trackCount) track\(draft.trackCount == 1 ? "" : "s") · \(draft.releaseDate)"
    }
}

private struct PublishDraftSummaryRow: View {
    let title: String
    let subtitle: String
    let artworkURL: String?

    var body: some View {
        HStack(spacing: 14) {
            PublishArtworkPreview(jpegData: nil, remoteURL: artworkURL, size: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.25))
        }
        .padding(.vertical, 4)
    }
}
