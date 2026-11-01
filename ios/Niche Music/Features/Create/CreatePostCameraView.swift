//
//  CreatePostCameraView.swift
//  Niche Music
//

import Kingfisher
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CreatePostCameraView: View {
    @ObservedObject var store: CreatePostStore
    @ObservedObject var draftStore: PostDraftStore

    let onNext: () -> Void
    let onClose: () -> Void

    @StateObject private var captureController = CreatePostCaptureController()

    @State private var showMusicPicker = false
    @State private var showDrafts = false
    @State private var pickedLibraryItem: PhotosPickerItem?

    private var usesLiveCamera: Bool {
        store.postType.allowsMedia
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if usesLiveCamera {
                liveCameraContent
            } else {
                pmoPlaceholder
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomControls
                .background(Color.black.opacity(0.92))
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.black.opacity(0.85), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose)
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                musicToolbarButton

                Button {
                    showDrafts = true
                } label: {
                    Image(systemName: "tray.full")
                }

                if usesLiveCamera, captureController.authorizationState == .authorized {
                    Button {
                        captureController.flipCamera()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                    }
                }
            }
        }
        .onAppear {
            syncCamera(active: usesLiveCamera)
        }
        .onChange(of: store.postType) { _, _ in
            syncCamera(active: usesLiveCamera)
        }
        .onDisappear {
            captureController.setActive(false, mode: store.captureMode)
        }
        .sheet(isPresented: $showMusicPicker) {
            CreatePostMusicPickerView(
                store: store,
                nicheOnly: store.postType.requiresNicheMusicOnly
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDrafts) {
            CreatePostDraftsSheet(draftStore: draftStore) { draft in
                captureController.setActive(false, mode: store.captureMode)
                let media = draftStore.loadMedia(for: draft)
                store.applyDraft(draft, mediaURL: media)
                if draft.mediaFileName != nil || draft.postType == .pmo {
                    advanceToCompose()
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: store.media) { _, media in
            if media == nil, usesLiveCamera {
                syncCamera(active: true)
            }
        }
        .onChange(of: pickedLibraryItem) { _, item in
            guard let item else { return }
            Task {
                await importLibraryItem(item)
                pickedLibraryItem = nil
            }
        }
    }

    @ViewBuilder
    private var liveCameraContent: some View {
        switch captureController.authorizationState {
        case .authorized:
            CreatePostCapturePreview(session: captureController.session)
                .ignoresSafeArea()
        case .denied, .unavailable:
            cameraUnavailablePlaceholder
        case .unknown:
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var pmoPlaceholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white.opacity(0.28))
            Text("Put me on to...")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cameraUnavailablePlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.white.opacity(0.28))
            Text("Choose from your library")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomControls: some View {
        VStack(spacing: 16) {
            if usesLiveCamera, captureController.authorizationState == .authorized {
                captureRow
            } else if store.postType == .pmo {
                Button {
                    advanceToCompose()
                } label: {
                    Text("Next")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(store.canContinueToCompose ? Color.white : Color.white.opacity(0.35), in: Capsule())
                }
                .disabled(!store.canContinueToCompose)
                .padding(.horizontal, 20)
            }

            postTypePicker
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var captureRow: some View {
        HStack {
            PhotosPicker(
                selection: $pickedLibraryItem,
                matching: store.postType == .video ? .videos : .images,
                photoLibrary: .shared()
            ) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
            }

            Spacer()

            Button {
                Task { await handleShutter() }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(captureController.isRecording ? Color.red : Color.white, lineWidth: 4)
                        .frame(width: 76, height: 76)
                    Circle()
                        .fill(store.postType == .video ? Color.red : Color.white)
                        .frame(
                            width: captureController.isRecording ? 34 : (store.postType == .video ? 58 : 64),
                            height: captureController.isRecording ? 34 : (store.postType == .video ? 58 : 64)
                        )
                }
            }
            .disabled(captureController.isCapturingPhoto)

            Spacer()

            Color.clear.frame(width: 52, height: 52)
        }
        .padding(.horizontal, 28)
    }

    private var postTypePicker: some View {
        Picker("Post type", selection: Binding(
            get: { store.postType },
            set: { store.setPostType($0) }
        )) {
            Text("Image").tag(CreatePostType.image)
            Text("Video").tag(CreatePostType.video)
            Text("Put Me On").tag(CreatePostType.pmo)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var musicToolbarButton: some View {
        Button {
            showMusicPicker = true
        } label: {
            if let music = store.music, let artworkUrl = music.artworkUrl,
               let url = URL(string: artworkUrl.replacingOccurrences(of: "{w}x{h}", with: "80x80")) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: "music.note")
            }
        }
    }

    private func advanceToCompose() {
        Task {
            await captureController.stop()
            onNext()
        }
    }

    private func syncCamera(active: Bool) {
        captureController.setActive(active, mode: store.captureMode)
    }

    private func handleShutter() async {
        if store.postType == .image {
            if let image = await captureController.capturePhoto() {
                await store.setCapturedImage(image)
                advanceToCompose()
            }
            return
        }

        if captureController.isRecording {
            if let url = await captureController.toggleVideoRecording() {
                await store.setCapturedVideo(from: url)
                advanceToCompose()
            }
        } else {
            await captureController.toggleVideoRecording()
        }
    }

    private func importLibraryItem(_ item: PhotosPickerItem) async {
        await captureController.stop()

        if store.postType == .video {
            if let movie = try? await item.loadTransferable(type: CreatePostPickedMovie.self) {
                await store.setCapturedVideo(from: movie.url)
                advanceToCompose()
            }
            return
        }

        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            await store.setCapturedImage(image)
            advanceToCompose()
        }
    }
}

private struct CreatePostPickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let destination = CreatePostMediaSupport.temporaryMediaURL(kind: .video)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: received.file, to: destination)
            return CreatePostPickedMovie(url: destination)
        }
    }
}
