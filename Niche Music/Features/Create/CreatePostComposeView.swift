//
//  CreatePostComposeView.swift
//  Niche Music
//

import AVKit
import Kingfisher
import SwiftUI
import UIKit

struct CreatePostComposeView: View {
    @ObservedObject var store: CreatePostStore
    @ObservedObject var draftStore: PostDraftStore

    let onPublish: () -> Void

    @FocusState private var captionFocused: Bool
    @State private var showMusicPicker = false
    @State private var draftSavedMessage: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                if store.postType.allowsMedia {
                    previewSection
                }

                captionSection

                musicSection

                visibilitySection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.backgroundColor.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture {
            captionFocused = false
        }
        .navigationTitle("New Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Theme.backgroundColor, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    saveDraft()
                }
                .foregroundStyle(.white.opacity(0.82))
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onPublish) {
                Text("Post")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(store.canPublish ? Theme.accentColor : Theme.accentColor.opacity(0.35), in: Capsule())
            }
            .disabled(!store.canPublish)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(Theme.backgroundColor.opacity(0.96))
        }
        .sheet(isPresented: $showMusicPicker) {
            CreatePostMusicPickerView(
                store: store,
                nicheOnly: store.postType.requiresNicheMusicOnly
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .top) {
            if let draftSavedMessage {
                Text(draftSavedMessage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.72), in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if let media = store.media {
            VStack(alignment: .leading, spacing: 10) {
                Text("Preview")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.48))

                CreatePostMediaPreview(media: media)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(previewAspectRatio(for: media), contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var captionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.postType == .pmo ? "Prompt" : "Caption")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.48))

            TextField(
                store.postType == .pmo ? "Put me on to songs like..." : "Write a caption...",
                text: $store.caption,
                axis: .vertical
            )
            .focused($captionFocused)
            .lineLimit(3...8)
            .font(.system(size: 16))
            .foregroundStyle(.white)
            .padding(14)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var musicSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Music")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.48))

            Button {
                showMusicPicker = true
            } label: {
                HStack(spacing: 12) {
                    if let music = store.music {
                        composeMusicPreview(music)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Theme.accentColor)
                        Text("Add Song")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.82))
                        Spacer()
                    }
                }
                .padding(14)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Visibility")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.48))

            Picker("Visibility", selection: $store.visibility) {
                Text("Public").tag(PostVisibility.public)
                Text("Private").tag(PostVisibility.private)
            }
            .pickerStyle(.segmented)
        }
    }

    private func previewAspectRatio(for media: CreatePostLocalMedia) -> CGFloat {
        let width = max(CGFloat(media.width), 1)
        let height = max(CGFloat(media.height), 1)
        let ratio = width / height
        return min(max(ratio, 0.55), 1.78)
    }

    @ViewBuilder
    private func composeMusicPreview(_ music: CreatePostMusicSelection) -> some View {
        HStack(spacing: 12) {
            Group {
                if let artworkUrl = music.artworkUrl, let url = URL(string: artworkUrl.replacingOccurrences(of: "{w}x{h}", with: "120x120")) {
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
                Text(music.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(music.artistName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }

            Spacer()

            Button {
                store.music = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }

    private func saveDraft() {
        do {
            _ = try store.saveDraft(using: draftStore)
            draftSavedMessage = "Draft saved"
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                draftSavedMessage = nil
            }
        } catch {
            draftSavedMessage = "Couldn't save draft"
        }
    }
}

private struct CreatePostMediaPreview: View {
    let media: CreatePostLocalMedia

    var body: some View {
        Group {
            if media.kind == .image, let image = UIImage(contentsOfFile: media.fileURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                VideoPlayer(player: AVPlayer(url: media.fileURL))
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.06))
    }
}
