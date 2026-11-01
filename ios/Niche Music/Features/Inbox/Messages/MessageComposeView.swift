//
//  MessageComposeView.swift
//  Niche Music
//

import SwiftUI
import Kingfisher

struct MessageComposeView: View {
    let initialRecipient: MessageComposeRecipient?
    let initialConversationId: String?

    @EnvironmentObject private var messagesStore: MessagesStore
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var friends: [MessageUserSummary] = []
    @State private var isLoadingFriends = false
    @State private var isOpeningThread = false
    @State private var selectedChat: ChatPreview?
    @State private var lookupError: String?
    @State private var didAutoOpen = false

    private var filteredFriends: [MessageUserSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return friends }
        return friends.filter {
            $0.username.lowercased().contains(query)
                || ($0.displayName?.lowercased().contains(query) ?? false)
        }
    }

    private var filteredChats: [ChatPreview] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return messagesStore.chats }
        return messagesStore.chats.filter {
            $0.name.lowercased().contains(query)
                || $0.subtitle.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        friendsSection
                    } else {
                        conversationsSection
                    }
                }
                .padding(.bottom, 120)
            }
        }
        .background(Theme.inboxBackgroundColor.ignoresSafeArea())
        .navigationTitle("New Message")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Theme.inboxBackgroundColor, for: .navigationBar)
        .navigationDestination(item: $selectedChat) { chat in
            MessageThreadView(chat: chat)
                .toolbarVisibility(.hidden, for: .tabBar)
        }
        .overlay {
            if isOpeningThread {
                ProgressView()
                    .tint(.white)
            }
        }
        .task {
            await loadFriendsIfNeeded()
            await autoOpenInitialRecipientIfNeeded()
            await autoOpenInitialConversationIfNeeded()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Text("To:")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))

            TextField("Search friends", text: $searchText)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    Task { await tryOpenUsernameLookup() }
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var friendsSection: some View {
        if isLoadingFriends && friends.isEmpty {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        } else if filteredFriends.isEmpty {
            VStack(spacing: 8) {
                Text(lookupError ?? "No friends found")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
            }
        } else {
            sectionHeader("Friends")
            ForEach(filteredFriends) { friend in
                friendRow(friend)
            }
        }
    }

    @ViewBuilder
    private var conversationsSection: some View {
        if messagesStore.isLoadingInbox && messagesStore.chats.isEmpty {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        } else if messagesStore.chats.isEmpty {
            Text("No conversations yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        } else {
            sectionHeader("Messages")
            ForEach(filteredChats) { chat in
                Button {
                    selectedChat = chat
                } label: {
                    composeChatRow(chat)
                }
                .buttonStyle(.plain)
            }
        }

        if !friends.isEmpty {
            sectionHeader("Friends")
                .padding(.top, 12)
            ForEach(friends) { friend in
                friendRow(friend)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.42))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)
    }

    private func friendRow(_ friend: MessageUserSummary) -> some View {
        Button {
            Task { await openFriend(friend) }
        } label: {
            HStack(spacing: 12) {
                composeAvatar(urlString: friend.avatarUrl, size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(friend.resolvedDisplayName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("@\(friend.username)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func composeChatRow(_ chat: ChatPreview) -> some View {
        HStack(spacing: 12) {
            ChatAvatar(chat: chat, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(chat.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("· \(chat.time)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                }

                Text(chat.lastMessage)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.46))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func composeAvatar(urlString: String?, size: CGFloat) -> some View {
        if let urlString, let url = URL(string: urlString) {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.34))
                        .foregroundStyle(.white.opacity(0.45))
                }
        }
    }

    private func loadFriendsIfNeeded() async {
        guard friends.isEmpty else { return }
        isLoadingFriends = true
        defer { isLoadingFriends = false }

        do {
            friends = try await MessagesService.shared.fetchFriends()
            lookupError = nil
        } catch {
            lookupError = "Couldn't load friends"
        }

        if messagesStore.chats.isEmpty {
            await messagesStore.refreshInbox()
        }
    }

    private func autoOpenInitialRecipientIfNeeded() async {
        guard !didAutoOpen, let recipient = initialRecipient else { return }
        didAutoOpen = true
        await openRecipient(recipient, conversationId: initialConversationId)
    }

    private func autoOpenInitialConversationIfNeeded() async {
        guard !didAutoOpen,
              initialRecipient == nil,
              let conversationId = initialConversationId else { return }
        didAutoOpen = true
        isOpeningThread = true
        defer { isOpeningThread = false }

        await messagesStore.refreshInbox()
        if let chat = messagesStore.chats.first(where: { $0.id == conversationId }) {
            selectedChat = chat
        }
    }

    private func tryOpenUsernameLookup() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        if let friend = friends.first(where: {
            $0.username.lowercased() == query.lowercased()
                || $0.resolvedDisplayName.lowercased() == query.lowercased()
        }) {
            await openFriend(friend)
            return
        }

        let username = query.hasPrefix("@") ? String(query.dropFirst()) : query
        guard !username.isEmpty else { return }

        isOpeningThread = true
        defer { isOpeningThread = false }

        do {
            let user = try await MessagesService.shared.lookupUser(username: username)
            await openFriend(user)
        } catch {
            lookupError = "No user found for @\(username)"
        }
    }

    private func openFriend(_ friend: MessageUserSummary) async {
        let recipient = MessageComposeRecipient(user: friend)
        await openRecipient(recipient, conversationId: nil)
    }

    private func openRecipient(
        _ recipient: MessageComposeRecipient,
        conversationId: String?
    ) async {
        isOpeningThread = true
        defer { isOpeningThread = false }

        let resolvedConversationId: String
        if let conversationId {
            resolvedConversationId = conversationId
        } else {
            do {
                resolvedConversationId = try await MessagesService.shared.ensureDM(otherUserId: recipient.id)
            } catch {
                lookupError = "Couldn't start a conversation"
                return
            }
        }

        await messagesStore.refreshInbox()
        selectedChat = messagesStore.chatPreview(
            conversationId: resolvedConversationId,
            recipient: recipient
        )
    }
}
