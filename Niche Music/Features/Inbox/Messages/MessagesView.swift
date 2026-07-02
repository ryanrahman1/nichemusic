//
//  MessagesView.swift
//  Niche Music
//
//  Created by Ryan Rahman on 6/9/26.
//

import SwiftUI
import Kingfisher

struct MessagesView: View {
    @EnvironmentObject private var messagesStore: MessagesStore

    var body: some View {
        let _ = messagesStore.typingRevision

        return Group {
            if messagesStore.isLoadingInbox && messagesStore.chats.isEmpty {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
            } else if let error = messagesStore.inboxError, messagesStore.chats.isEmpty {
                VStack(spacing: 12) {
                    Text(error)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Button("Try again") {
                        Task { await messagesStore.refreshInbox() }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
            } else if messagesStore.chats.isEmpty {
                Text("No messages yet")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(messagesStore.chats) { chat in
                        NavigationLink {
                            MessageThreadView(chat: chat)
                                .toolbarVisibility(.hidden, for: .tabBar)
                        } label: {
                            chatRow(chat)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task {
            if messagesStore.chats.isEmpty {
                await messagesStore.refreshInbox()
            }
        }
    }

    private func chatRow(_ chat: ChatPreview) -> some View {
        let typingLabel = messagesStore.typingLabel(for: chat)

        return HStack(spacing: 12) {
            ChatAvatar(chat: chat, size: 54)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(chat.name)
                        .font(.system(size: 16, weight: chat.unreadCount > 0 ? .semibold : .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("· \(chat.time)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                }

                Text(typingLabel ?? chat.lastMessage)
                    .font(.system(size: 14))
                    .foregroundStyle(
                        typingLabel != nil
                            ? Theme.accentColor.opacity(0.92)
                            : (chat.unreadCount > 0 ? .white.opacity(0.8) : .white.opacity(0.46))
                    )
                    .lineLimit(1)
            }

            Spacer()

            if chat.unreadCount > 0 {
                Circle()
                    .fill(Theme.accentColor)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
