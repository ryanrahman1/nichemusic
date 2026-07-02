//
//  ChatInfoViews.swift
//  Niche Music
//
//  Created by Ryan Rahman on 6/9/26.
//

import SwiftUI
import Kingfisher

struct DMInfoView: View {
    let chat: ChatPreview

    var body: some View {
        VStack(spacing: 22) {
            ChatAvatar(chat: chat, size: 86)

            VStack(spacing: 4) {
                Text(chat.name)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)

                Text(chat.subtitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }

            if let username = chat.otherUsername {
                ProfileUsernameLink(username: username) {
                    Text("View Profile")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            } else {
                Text("View Profile")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Spacer()
        }
        .padding(24)
        .background(Theme.backgroundColor.ignoresSafeArea())
    }
}

struct GroupChatInfoView: View {
    @State private var groupName: String
    @State private var showComingSoon = false

    let chat: ChatPreview

    init(chat: ChatPreview) {
        self.chat = chat
        _groupName = State(initialValue: chat.name)
    }

    private var members: [String] {
        chat.memberNames.isEmpty ? [chat.name] : chat.memberNames
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Group")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)

            TextField("Group name", text: $groupName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
                .disabled(true)
                .padding()
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                showComingSoon = true
            } label: {
                Label("Invite people", systemImage: "person.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 10) {
                Text("People")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))

                ForEach(members, id: \.self) { name in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(.white.opacity(0.12))
                            .frame(width: 42, height: 42)
                            .overlay {
                                Text(String(name.prefix(1)).uppercased())
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.55))
                            }

                        Text(name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)

                        Spacer()
                    }
                    .padding(.vertical, 5)
                }
            }

            Spacer()
        }
        .padding(24)
        .background(Theme.backgroundColor.ignoresSafeArea())
        .comingSoonAlert(isPresented: $showComingSoon)
    }
}

private enum AttachDestination: Hashable {
    case song, album, artist, profile
}

struct AttachmentMenuSheet: View {
    let chat: ChatPreview
    /// Called when the user taps GIF — the parent dismisses the sheet then presents Giphy.
    var onGifTapped: (() -> Void)?

    @EnvironmentObject private var messagesStore: MessagesStore
    @Environment(\.dismiss) private var dismiss

    @State private var path: [AttachDestination] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 22) {
                Text("Send")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 14) {
                    attachTile("Song", icon: "music.note")      { path.append(.song) }
                    attachTile("Album", icon: "square.stack")    { path.append(.album) }
                    attachTile("Artist", icon: "person.crop.circle") { path.append(.artist) }
                    attachTile("GIF", icon: "sparkles") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            onGifTapped?()
                        }
                    }
                    attachTile("Profile", icon: "person")       { path.append(.profile) }
                }

                Spacer()
            }
            .padding(24)
            .background(Theme.backgroundColor.ignoresSafeArea())
            .navigationDestination(for: AttachDestination.self) { destination in
                switch destination {
                case .song:
                    MessageSongPickerView(chat: chat, onSent: { dismiss() })
                        .background(Theme.backgroundColor.ignoresSafeArea())
                case .album:
                    MessageAlbumPickerView(chat: chat, onSent: { dismiss() })
                        .background(Theme.backgroundColor.ignoresSafeArea())
                case .artist:
                    MessageArtistPickerView(chat: chat, onSent: { dismiss() })
                        .background(Theme.backgroundColor.ignoresSafeArea())
                case .profile:
                    MessageProfilePickerView(chat: chat, onSent: { dismiss() })
                        .background(Theme.backgroundColor.ignoresSafeArea())
                }
            }
        }
        .background(Theme.backgroundColor.ignoresSafeArea())
    }

    private func attachTile(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))

                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct ChatAvatar: View {
    let chat: ChatPreview
    let size: CGFloat

    var body: some View {
        Group {
            if chat.kind == .dm,
               let avatarURL = chat.avatarURL,
               let url = URL(string: avatarURL) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
            } else if chat.kind == .group {
                ZStack {
                    Circle().fill(.white.opacity(0.12))

                    Image(systemName: "person.2.fill")
                        .foregroundStyle(.white.opacity(0.5))
                }
            } else {
                Circle()
                    .fill(.white.opacity(0.12))
                    .overlay {
                        Text(String(chat.name.prefix(1)).uppercased())
                            .font(.system(size: size * 0.34, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
