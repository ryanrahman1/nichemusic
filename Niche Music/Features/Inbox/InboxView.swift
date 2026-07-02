//
//  InboxView.swift
//  Niche Music
//

import SwiftUI
import Kingfisher

private struct InboxGamePreview: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let imageName: String?
    let systemFallback: String
}

struct InboxView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var musicMatchesStore: MusicMatchesStore
    @EnvironmentObject private var triviaStore: TriviaStore
    @EnvironmentObject private var auxBattleStore: AuxBattleStore
    @EnvironmentObject private var messagesStore: MessagesStore
    @EnvironmentObject private var musicPlayer: MusicPlayer

    @StateObject private var notificationsStore = NotificationsStore()

    @State private var presentedMatch: MusicMatch?
    @State private var showDailyTrivia = false
    @State private var showAuxBattle = false
    @State private var showNotifications = false
    @State private var isLoadingMatch = false
    @State private var matchError: String?
    @State private var composeNavigation: MessageComposeIntent?
    @State private var deepLinkThread: ChatPreview?

    private let games: [InboxGamePreview] = [
        InboxGamePreview(
            id: "daily_trivia",
            title: "Daily Trivia",
            subtitle: "Test your music knowledge",
            imageName: "DailyTrivia",
            systemFallback: "questionmark.circle"
        ),
        InboxGamePreview(
            id: "aux",
            title: "Aux Battle",
            subtitle: "Pass the aux",
            imageName: "AuxBattle",
            systemFallback: "slider.horizontal.3"
        ),
        InboxGamePreview(
            id: "match",
            title: "Music Match",
            subtitle: "Latest match",
            imageName: "MusicMatch",
            systemFallback: "waveform.path"
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Games rail
                    VStack(alignment: .leading, spacing: 12) {
                        if let matchError {
                            Text(matchError)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textSecondaryColor)
                                .padding(.horizontal, 18)
                        }

                        gamesRail
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                    // Section header
                    Text("Messages")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)

                    // Inline messages list — no nested ScrollView
                    MessagesView()
                }
                .padding(.bottom, 120)
            }
            .background(Theme.inboxBackgroundColor.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        composeNavigation = MessageComposeIntent(recipient: nil, conversationId: nil)
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNotifications = true
                    } label: {
                        Image(systemName: "bell")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(item: $composeNavigation) { intent in
                MessageComposeView(
                    initialRecipient: intent.recipient,
                    initialConversationId: intent.conversationId
                )
                .toolbarVisibility(.hidden, for: .tabBar)
            }
            .navigationDestination(item: $deepLinkThread) { chat in
                MessageThreadView(chat: chat)
                    .toolbarVisibility(.hidden, for: .tabBar)
            }
            .onChange(of: messagesStore.composeIntent) { _, intent in
                guard let intent else { return }
                composeNavigation = intent
                messagesStore.composeIntent = nil
            }
            .onAppear {
                if let intent = messagesStore.composeIntent {
                    composeNavigation = intent
                    messagesStore.composeIntent = nil
                }
            }
            .onChange(of: messagesStore.pendingThreadChat) { _, chat in
                guard let chat else { return }
                deepLinkThread = chat
                messagesStore.pendingThreadChat = nil
            }
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsSheetView(store: notificationsStore)
                .environmentObject(profileStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $presentedMatch) { match in
            MusicMatchFullscreenView(
                match: match,
                viewerAvatarURL: viewerAvatarURL,
                store: musicMatchesStore,
                onOpenInbox: nil,
                onOpenConversation: { conversationId, otherUser in
                    Task {
                        await messagesStore.openConversationFromMatch(
                            conversationId: conversationId,
                            recipient: MessageComposeRecipient(otherUser: otherUser)
                        )
                    }
                },
                onDismiss: { presentedMatch = nil }
            )
        }
        .fullScreenCover(isPresented: $showDailyTrivia) {
            DailyTriviaFullscreenView(
                store: triviaStore,
                onDismiss: { showDailyTrivia = false }
            )
        }
        .fullScreenCover(isPresented: $showAuxBattle) {
            AuxBattleFullscreenView(
                store: auxBattleStore,
                onDismiss: {
                    showAuxBattle = false
                    auxBattleStore.resetSession()
                }
            )
            .environmentObject(session)
            .environmentObject(musicPlayer)
        }
    }

    private var gamesRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(games) { game in
                    InboxGameCard(
                        title: game.title,
                        subtitle: game.id == "match" && isLoadingMatch ? "Loading..." : game.subtitle,
                        imageName: game.imageName,
                        systemFallback: game.systemFallback
                    ) {
                        if game.id == "match" {
                            Task { await openLatestMatch() }
                        } else if game.id == "aux" {
                            haptic(.light)
                            musicPlayer.stop(clearQueue: true, clearHistory: true)
                            FeedPlayerCache.shared.stopAll()
                            showAuxBattle = true
                        } else if game.id == "daily_trivia" {
                            haptic(.light)
                            showDailyTrivia = true
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var viewerAvatarURL: URL? {
        guard let urlString = session.currentUser?.avatarUrl else { return nil }
        return URL(string: urlString)
    }

    private func openLatestMatch() async {
        isLoadingMatch = true
        matchError = nil
        if let match = await musicMatchesStore.fetchLatestMatch() {
            presentedMatch = match
        } else {
            matchError = "No music match yet"
        }
        isLoadingMatch = false
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

private struct InboxGameCard: View {
    let title: String
    let subtitle: String
    let imageName: String?
    let systemFallback: String
    let action: () -> Void

    private let width: CGFloat = 230
    private let height: CGFloat = 126

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                gameArtwork

                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
                .padding(13)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var gameArtwork: some View {
        if let imageName {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
        } else {
            ZStack {
                Rectangle()
                    .fill(.white.opacity(0.075))

                Image(systemName: systemFallback)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white.opacity(0.32))
            }
        }
    }
}

#Preview {
    InboxView()
        .environmentObject(SessionStore(bootstrap: false, previewState: .signedIn(.preview)))
        .environmentObject(ProfileStore())
        .environmentObject(MusicMatchesStore())
        .environmentObject(TriviaStore())
        .environmentObject(AuxBattleStore())
        .environmentObject(MessagesStore())
        .environmentObject(MusicPlayer())
}
