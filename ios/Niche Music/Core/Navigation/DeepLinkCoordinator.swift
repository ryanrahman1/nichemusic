//
//  DeepLinkCoordinator.swift
//  Niche Music
//

import Combine
import SwiftUI

@MainActor
final class DeepLinkCoordinator: ObservableObject {
    @Published private(set) var pendingDestination: DeepLinkDestination?

    private var session: SessionStore?
    private var appNavigation: AppNavigationRouter?
    private var messagesStore: MessagesStore?

    func configure(
        session: SessionStore,
        appNavigation: AppNavigationRouter,
        messagesStore: MessagesStore
    ) {
        self.session = session
        self.appNavigation = appNavigation
        self.messagesStore = messagesStore
    }

    func handleIncomingURL(_ url: URL) {
        handleIncomingURLString(url.absoluteString)
    }

    func handleIncomingURLString(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if trimmed.lowercased().hasPrefix("nichemusic:") {
            guard let destination = NicheURLParser.parse(trimmed) else { return }
            enqueueOrOpen(destination)
            return
        }

        guard let destination = NicheURLParser.parse(trimmed) else { return }
        enqueueOrOpen(destination)
    }

    func handleNotification(_ notification: AppNotification) {
        guard let destination = NotificationTargetResolver.destination(for: notification) else { return }
        enqueueOrOpen(destination)
    }

    func handlePushPayload(_ userInfo: [AnyHashable: Any]) {
        guard let destination = NotificationTargetResolver.destination(fromPushPayload: userInfo) else { return }
        enqueueOrOpen(destination)
    }

    func flushPendingIfAuthenticated() {
        guard isAuthenticated, let pendingDestination else { return }
        self.pendingDestination = nil
        Task {
            await open(pendingDestination)
        }
    }

    private var isAuthenticated: Bool {
        if case .signedIn = session?.state {
            return true
        }
        return false
    }

    private func enqueueOrOpen(_ destination: DeepLinkDestination) {
        guard isAuthenticated else {
            pendingDestination = destination
            return
        }

        Task {
            await open(destination)
        }
    }

    func open(_ destination: DeepLinkDestination) async {
        guard let appNavigation else { return }

        switch destination {
        case .post(let id, _):
            appNavigation.selectedTab = 0
            appNavigation.modalPostRoute = PostDetailNavigationRoute(postId: id)

        case .profile(let username):
            appNavigation.selectedTab = 0
            appNavigation.modalProfileRoute = ProfileNavigationRoute(username: username)

        case .track(let reference):
            appNavigation.selectedTab = 0
            appNavigation.modalTrackDetailRoute = TrackDetailNavigationRoute(reference: reference)

        case .shareTrack(let id):
            let resolved = await ShareEntityResolver.resolveTrackDestination(trackId: id)
            await open(resolved)

        case .shareArtist(let id):
            guard let resolved = await ShareEntityResolver.resolveArtistDestination(artistId: id) else { return }
            await open(resolved)

        case .appleArtist(let sourceId):
            appNavigation.selectedTab = 1
            appNavigation.modalAppleArtistRoute = AppleArtistNavigationRoute(sourceId: sourceId)

        case .appleAlbum(let sourceId):
            appNavigation.selectedTab = 1
            appNavigation.modalAppleAlbumRoute = AppleAlbumNavigationRoute(sourceId: sourceId)

        case .nicheAlbum(let id):
            appNavigation.selectedTab = 1
            appNavigation.modalNicheAlbumRoute = NicheAlbumNavigationRoute(albumId: id)

        case .playlist(let id):
            appNavigation.selectedTab = 2
            appNavigation.modalPlaylistRoute = PlaylistDetailNavigationRoute(playlistId: id)

        case .conversation(let id):
            appNavigation.selectedTab = 3
            await messagesStore?.openConversation(conversationId: id)

        case .externalURL(let url):
            await UIApplication.shared.open(url)
        }
    }
}
