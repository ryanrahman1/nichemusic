//
//  Niche_MusicApp.swift
//  Niche Music
//

import SwiftUI
import GoogleMobileAds
import GiphyUISDK

@main
struct nichemusicApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var session = SessionStore()
    @StateObject private var emailVerification = EmailVerificationStore()
    @StateObject private var musicStore = MusicStore()
    @StateObject private var profileStore = ProfileStore()
    @StateObject private var postsStore = PostsStore()
    @StateObject private var postCommentsStore = PostCommentsStore()
    @StateObject private var trackCommentsStore = TrackCommentsStore()
    @StateObject private var appNavigation = AppNavigationRouter()
    @StateObject private var deepLinkCoordinator = DeepLinkCoordinator()
    @StateObject private var musicMatchesStore = MusicMatchesStore()
    @StateObject private var triviaStore = TriviaStore()
    @StateObject private var auxBattleStore = AuxBattleStore()
    @StateObject private var libraryStore = LibraryStore()
    @StateObject private var messagesStore = MessagesStore()
    @StateObject private var playlistStore = PlaylistStore()

    init() {
        MobileAds.shared.start()
        Giphy.configure(apiKey: GiphyConfig.apiKey)
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(session)
                .environmentObject(emailVerification)
                .environmentObject(musicStore)
                .environmentObject(profileStore)
                .environmentObject(postsStore)
                .environmentObject(postCommentsStore)
                .environmentObject(trackCommentsStore)
                .environmentObject(appNavigation)
                .environmentObject(deepLinkCoordinator)
                .environmentObject(musicMatchesStore)
                .environmentObject(triviaStore)
                .environmentObject(auxBattleStore)
                .environmentObject(messagesStore)
                .environmentObject(libraryStore)
                .environmentObject(playlistStore)
        }
    }
}
