//
//  PublishSharedComponents.swift
//  Niche Music
//

import Kingfisher
import PhotosUI
import SwiftUI
import UIKit

enum PublishKeyboardFocus: Hashable {
    case trackName
    case bpm
    case releaseName
}

extension View {
    func publishDismissKeyboardOnTap(focus: FocusState<PublishKeyboardFocus?>.Binding) -> some View {
        scrollDismissesKeyboard(.interactively)
    }

    func publishKeyboardToolbar(focus: FocusState<PublishKeyboardFocus?>.Binding) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focus.wrappedValue = nil
                }
            }
        }
    }
}

struct PublishFormPickerRow: View {
    let title: String
    @Binding var selection: PhotosPickerItem?
    let matching: PHPickerFilter

    var body: some View {
        PhotosPicker(selection: $selection, matching: matching) {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(Theme.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}

struct PublishFormBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
            .background(Theme.backgroundColor.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
    }
}

extension View {
    func publishFormStyle() -> some View {
        modifier(PublishFormBackground())
    }
}

struct PublishUploadStatusRow: View {
    let title: String
    let state: PublishUploadState

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.white)
            Spacer()
            statusView
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch state {
        case .waiting:
            Text("Waiting")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
        case .uploading:
            HStack(spacing: 8) {
                ProgressView().tint(.white).scaleEffect(0.8)
                Text("Uploading")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)
            }
        case .uploaded:
            Label("Uploaded", systemImage: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        case .failed(let message):
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.orange)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct PublishAudioFileRow: View {
    let fileName: String
    let state: PublishUploadState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Audio file")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))

            HStack(alignment: .center, spacing: 12) {
                Text(fileName)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)
                uploadStatus
            }
        }
    }

    @ViewBuilder
    private var uploadStatus: some View {
        switch state {
        case .waiting:
            Text("Waiting")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
        case .uploading:
            HStack(spacing: 8) {
                ProgressView().tint(.white).scaleEffect(0.8)
                Text("Uploading")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)
            }
        case .uploaded:
            Label("Uploaded", systemImage: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        case .failed(let message):
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.orange)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct PublishFullWidthArtworkPreview: View {
    let jpegData: Data?
    let remoteURL: String?
    var placeholderIcon: String = "music.note"

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            Group {
                if let jpegData, let image = UIImage(data: jpegData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if let remoteURL, let url = URL(string: remoteURL) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white.opacity(0.1)
                        .overlay {
                            VStack(spacing: 10) {
                                Image(systemName: placeholderIcon)
                                    .font(.system(size: 36))
                                    .foregroundStyle(.white.opacity(0.35))
                                Text("No artwork yet")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                        }
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct PublishFullWidthMomentPreview: View {
    let thumbnail: UIImage?
    let uploadState: PublishUploadState
    let fileLabel: String?

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            ZStack {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white.opacity(0.1)
                        .overlay {
                            VStack(spacing: 10) {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.white.opacity(0.35))
                                Text("No moment yet")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                        }
                }

                if uploadState.isUploading {
                    Color.black.opacity(0.45)
                    ProgressView().tint(.white)
                }

                VStack {
                    Spacer()
                    HStack {
                        if let fileLabel {
                            Text(fileLabel)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(uploadState.statusLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(uploadState.isUploaded ? .green : .white.opacity(0.85))
                    }
                    .padding(12)
                    .background(.black.opacity(0.55))
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct PublishArtworkPreview: View {
    let jpegData: Data?
    let remoteURL: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let jpegData, let image = UIImage(data: jpegData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let remoteURL, let url = URL(string: remoteURL) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.1)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.28))
                            .foregroundStyle(.white.opacity(0.35))
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct PublishTextFieldRow: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var limit: Int? = nil
    var focus: FocusState<PublishKeyboardFocus?>.Binding? = nil
    var focusValue: PublishKeyboardFocus? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                if let limit {
                    Text("\(text.count)/\(limit)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            Group {
                if let focus, let focusValue {
                    TextField(placeholder, text: $text)
                        .focused(focus, equals: focusValue)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .foregroundStyle(.white)
        }
        .onChange(of: text) { _, newValue in
            if let limit, newValue.count > limit {
                text = String(newValue.prefix(limit))
            }
        }
    }
}

struct PublishBottomActionBar: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isEnabled ? Theme.accentColor : Theme.accentColor.opacity(0.35), in: Capsule())
        }
        .disabled(!isEnabled)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Theme.backgroundColor.opacity(0.96))
    }
}

struct PublishBusyOverlay: View {
    let isVisible: Bool

    var body: some View {
        if isVisible {
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea()
                NicheProgress()
            }
        }
    }
}
