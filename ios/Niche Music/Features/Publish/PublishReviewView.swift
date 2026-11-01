//
//  PublishReviewView.swift
//  Niche Music
//

import SwiftUI

struct PublishSingleReviewView: View {
    @ObservedObject var store: PublishMusicStore
    let onPublished: (PublishMusicDestination) -> Void

    private var draft: PublishTrackDraft {
        if case .reviewSingle(let draft) = store.flow { return draft }
        return PublishTrackDraft(id: "")
    }

    private var issues: [String] {
        draft.validationIssues()
    }

    var body: some View {
        Form {
            Section {
                reviewRow("Track title", value: draft.name.isEmpty ? "—" : draft.name)
                reviewRow("Release date", value: PublishDateFormatting.apiString(from: draft.releaseDate))
                reviewRow("Visibility", value: draft.visibility.label)
                reviewRow("Explicit", value: draft.explicit ? "Yes" : "No")
                reviewRow("Duration", value: PublishMediaSupport.formattedDuration(ms: draft.durationMs))
                reviewRow("Audio", value: draft.audioUpload.statusLabel)
                reviewRow("Artwork", value: draft.artworkUpload.isUploaded || draft.pendingArtworkJPEG != nil ? "Added" : "Optional")
                reviewRow("Credits", value: "\(draft.credits.count) artist(s)")
            }
            .listRowBackground(Color.white.opacity(0.06))

            if !issues.isEmpty {
                warningSection(issues)
            }
        }
        .publishFormStyle()
        .navigationTitle("Review single")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Edit") {
                    store.flow = .single(draft)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            PublishBottomActionBar(
                title: "Publish",
                isEnabled: issues.isEmpty && !store.isBusy,
                action: publish
            )
        }
        .overlay { PublishBusyOverlay(isVisible: store.isBusy) }
    }

    private func publish() {
        Task {
            if let destination = await store.publishSingle() {
                onPublished(destination)
            }
        }
    }
}

struct PublishReleaseReviewView: View {
    @ObservedObject var store: PublishMusicStore
    let onPublished: (PublishMusicDestination) -> Void

    private var draft: PublishReleaseDraft {
        if case .reviewRelease(let draft) = store.flow { return draft }
        return PublishReleaseDraft(id: "", releaseType: .ep)
    }

    private var issues: [String] {
        draft.validationIssues()
    }

    var body: some View {
        Form {
            Section {
                reviewRow("Release title", value: draft.name.isEmpty ? "—" : draft.name)
                reviewRow("Type", value: draft.releaseType.label)
                reviewRow("Release date", value: PublishDateFormatting.apiString(from: draft.releaseDate))
                reviewRow("Visibility", value: draft.visibility.label)
                reviewRow("Artwork", value: draft.artworkUpload.statusLabel)
            }
            .listRowBackground(Color.white.opacity(0.06))

            Section("Tracklist") {
                ForEach(draft.tracks) { track in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("\(track.trackNumber). \(track.name.isEmpty ? "Untitled" : track.name)")
                                .foregroundStyle(.white)
                            Spacer()
                            Text(track.audioUpload.statusLabel)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(track.audioUpload.isUploaded ? .green : .orange)
                        }

                        if !track.validationIssues().isEmpty {
                            Text(track.validationIssues().joined(separator: ", "))
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .listRowBackground(Color.white.opacity(0.06))

            if !issues.isEmpty {
                warningSection(issues)
            }
        }
        .publishFormStyle()
        .navigationTitle("Review release")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Edit") {
                    store.flow = .release(draft)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            PublishBottomActionBar(
                title: "Publish",
                isEnabled: issues.isEmpty && !store.isBusy,
                action: publish
            )
        }
        .overlay { PublishBusyOverlay(isVisible: store.isBusy) }
    }

    private func publish() {
        Task {
            if let destination = await store.publishRelease() {
                onPublished(destination)
            }
        }
    }
}

@ViewBuilder
private func reviewRow(_ title: String, value: String) -> some View {
    HStack {
        Text(title)
            .foregroundStyle(.white)
        Spacer()
        Text(value)
            .foregroundStyle(.white.opacity(0.55))
            .multilineTextAlignment(.trailing)
    }
}

@ViewBuilder
private func warningSection(_ issues: [String]) -> some View {
    Section("Fix before publishing") {
        ForEach(issues, id: \.self) { issue in
            Label(issue, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 14))
        }
    }
}
