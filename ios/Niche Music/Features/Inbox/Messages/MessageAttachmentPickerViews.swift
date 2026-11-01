//
//  MessageAttachmentPickerViews.swift
//  Niche Music
//
//  Picker sheets for the five DM attachment types:
//  Song · Album · Artist · Profile  (GIF uses GiphyMediaPicker directly)
//

import SwiftUI
import Kingfisher

// MARK: – Song picker

struct MessageSongPickerView: View {
    let chat: ChatPreview
    var onSent: (() -> Void)?

    @EnvironmentObject private var messagesStore: MessagesStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [AppleMusicSearchSong] = []
    @State private var isSearching = false
    @State private var sendingId: String?

    var body: some View {
        VStack(spacing: 0) {
            pickerSearchBar("Search songs…", text: $query)

            if isSearching {
                pickerLoadingState
            } else if results.isEmpty {
                pickerEmptyState(icon: "music.note", hint: "Search for a song to share")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { song in
                            pickerRow(
                                imageURL: song.artworkURL,
                                title: song.title,
                                subtitle: song.artistName,
                                isSending: sendingId == song.id
                            ) { Task { await select(song) } }
                        }
                    }
                }
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .navigationTitle("Share a Song")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.backgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onChange(of: query) { _, q in Task { await search(q) } }
    }

    private func search(_ q: String) async {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { results = []; return }
        isSearching = true
        defer { isSearching = false }
        let found = try? await MessagesService.shared.searchAppleMusic(query: trimmed, types: "songs")
        results = found?.songs?.data ?? []
    }

    private func select(_ song: AppleMusicSearchSong) async {
        guard sendingId == nil else { return }
        sendingId = song.id
        // Resolve artwork template to a full-resolution URL string
        let artworkURLString: String? = {
            guard let template = song.attributes.artwork?.url else { return nil }
            return template
                .replacingOccurrences(of: "{w}", with: "480")
                .replacingOccurrences(of: "{h}", with: "480")
        }()
        await messagesStore.sendTrackShare(
            in: chat,
            appleSourceId: song.id,
            title: song.title,
            artistName: song.artistName,
            artworkURLString: artworkURLString
        )
        sendingId = nil
        onSent?()
        dismiss()
    }
}

// MARK: – Album picker

struct MessageAlbumPickerView: View {
    let chat: ChatPreview
    var onSent: (() -> Void)?

    @EnvironmentObject private var messagesStore: MessagesStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [AppleMusicSearchAlbum] = []
    @State private var isSearching = false
    @State private var sendingId: String?

    var body: some View {
        VStack(spacing: 0) {
            pickerSearchBar("Search albums…", text: $query)

            if isSearching {
                pickerLoadingState
            } else if results.isEmpty {
                pickerEmptyState(icon: "square.stack", hint: "Search for an album to share")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { album in
                            pickerRow(
                                imageURL: album.artworkURL,
                                title: album.attributes.name,
                                subtitle: album.artistName,
                                isSending: sendingId == album.id
                            ) { Task { await select(album) } }
                        }
                    }
                }
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .navigationTitle("Share an Album")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.backgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onChange(of: query) { _, q in Task { await search(q) } }
    }

    private func search(_ q: String) async {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { results = []; return }
        isSearching = true
        defer { isSearching = false }
        let found = try? await MessagesService.shared.searchAppleMusic(query: trimmed, types: "albums")
        results = found?.albums?.data ?? []
    }

    private func select(_ album: AppleMusicSearchAlbum) async {
        guard sendingId == nil else { return }
        sendingId = album.id
        let artworkURLString: String? = {
            guard let template = album.attributes.artwork?.url else { return nil }
            return template
                .replacingOccurrences(of: "{w}", with: "480")
                .replacingOccurrences(of: "{h}", with: "480")
        }()
        await messagesStore.sendAlbumShare(
            in: chat,
            appleSourceId: album.id,
            title: album.attributes.name,
            artistName: album.artistName,
            artworkURLString: artworkURLString
        )
        sendingId = nil
        onSent?()
        dismiss()
    }
}

// MARK: – Artist picker

struct MessageArtistPickerView: View {
    let chat: ChatPreview
    var onSent: (() -> Void)?

    @EnvironmentObject private var messagesStore: MessagesStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [AppleMusicSearchArtist] = []
    @State private var isSearching = false
    @State private var sendingId: String?

    var body: some View {
        VStack(spacing: 0) {
            pickerSearchBar("Search artists…", text: $query)

            if isSearching {
                pickerLoadingState
            } else if results.isEmpty {
                pickerEmptyState(icon: "person.crop.circle", hint: "Search for an artist to share")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { artist in
                            pickerRow(
                                imageURL: artist.artworkURL,
                                title: artist.attributes.name,
                                subtitle: nil,
                                isCircleImage: true,
                                isSending: sendingId == artist.id
                            ) { Task { await select(artist) } }
                        }
                    }
                }
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .navigationTitle("Share an Artist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.backgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onChange(of: query) { _, q in Task { await search(q) } }
    }

    private func search(_ q: String) async {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { results = []; return }
        isSearching = true
        defer { isSearching = false }
        let found = try? await MessagesService.shared.searchAppleMusic(query: trimmed, types: "artists")
        results = found?.artists?.data ?? []
    }

    private func select(_ artist: AppleMusicSearchArtist) async {
        guard sendingId == nil else { return }
        sendingId = artist.id
        let imageURLString: String? = {
            guard let template = artist.attributes.artwork?.url else { return nil }
            return template
                .replacingOccurrences(of: "{w}", with: "480")
                .replacingOccurrences(of: "{h}", with: "480")
        }()
        await messagesStore.sendArtistShare(
            in: chat,
            appleSourceId: artist.id,
            name: artist.attributes.name,
            imageURLString: imageURLString
        )
        sendingId = nil
        onSent?()
        dismiss()
    }
}

// MARK: – Profile picker

struct MessageProfilePickerView: View {
    let chat: ChatPreview
    var onSent: (() -> Void)?

    @EnvironmentObject private var messagesStore: MessagesStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var foundUser: MessageUserSummary?
    @State private var isSearching = false
    @State private var notFound = false
    @State private var isSending = false

    var body: some View {
        VStack(spacing: 0) {
            pickerSearchBar("Enter a username...", text: $query)

            if isSearching {
                pickerLoadingState
            } else if let user = foundUser {
                userResultView(user)
            } else if notFound {
                pickerEmptyState(icon: "person.slash", hint: "No user found for \"\(query)\"")
            } else {
                pickerEmptyState(icon: "person", hint: "Type a username to look them up")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .navigationTitle("Share a Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.backgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onChange(of: query) { _, q in Task { await lookup(q) } }
    }

    private func userResultView(_ user: MessageUserSummary) -> some View {
        VStack(spacing: 0) {
            pickerRow(
                imageURL: user.avatarUrl.flatMap { URL(string: $0) },
                title: user.displayName ?? user.username,
                subtitle: "@\(user.username)",
                isCircleImage: true,
                isSending: isSending
            ) { Task { await select(user) } }
        }
        .padding(.top, 10)
    }

    private func lookup(_ q: String) async {
        let trimmed = q
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "@", with: "")
        guard trimmed.count >= 2 else { foundUser = nil; notFound = false; return }
        isSearching = true
        notFound = false
        defer { isSearching = false }
        do {
            foundUser = try await MessagesService.shared.lookupUser(username: trimmed)
        } catch {
            foundUser = nil
            notFound = true
        }
    }

    private func select(_ user: MessageUserSummary) async {
        guard !isSending else { return }
        isSending = true
        await messagesStore.sendProfileShare(
            in: chat,
            userId: user.id,
            username: user.username,
            displayName: user.displayName,
            avatarURLString: user.avatarUrl
        )
        isSending = false
        onSent?()
        dismiss()
    }
}

// MARK: – Shared UI helpers (file-private)

private func pickerSearchBar(_ placeholder: String, text: Binding<String>) -> some View {
    HStack(spacing: 10) {
        Image(systemName: "magnifyingglass")
            .foregroundStyle(.white.opacity(0.4))
        TextField(placeholder, text: text)
            .foregroundStyle(.white)
            .autocorrectionDisabled()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
}

private var pickerLoadingState: some View {
    VStack {
        Spacer()
        ProgressView().tint(.white.opacity(0.6))
        Spacer()
    }
}

private func pickerEmptyState(icon: String, hint: String) -> some View {
    VStack(spacing: 10) {
        Spacer()
        Image(systemName: icon)
            .font(.system(size: 32))
            .foregroundStyle(.white.opacity(0.2))
        Text(hint)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white.opacity(0.38))
            .multilineTextAlignment(.center)
        Spacer()
    }
}

/// A single tappable row used by all pickers.
/// Returns a VStack containing the row + a thin divider.
private func pickerRow(
    imageURL: URL?,
    title: String,
    subtitle: String?,
    isCircleImage: Bool = false,
    isSending: Bool,
    onTap: @escaping () -> Void
) -> some View {
    VStack(spacing: 0) {
        Button(action: onTap) {
            HStack(spacing: 13) {
                Group {
                    if let url = imageURL {
                        KFImage(url)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.white.opacity(0.08)
                            .overlay {
                                Image(systemName: isCircleImage ? "person.fill" : "music.note")
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                    }
                }
                .frame(width: 46, height: 46)
                .clipShape(
                    isCircleImage
                        ? AnyShape(Circle())
                        : AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if isSending {
                    ProgressView()
                        .tint(.white.opacity(0.5))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSending)

        Rectangle()
            .fill(.white.opacity(0.07))
            .frame(height: 1)
    }
}
