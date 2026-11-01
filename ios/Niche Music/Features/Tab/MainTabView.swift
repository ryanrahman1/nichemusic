//
//  MainTabView.swift
//  Niche Music
//
//  Created by Ryan Rahman on 5/24/26.
//

import SwiftUI
import UIKit
import Kingfisher

struct MainTabView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var musicStore: MusicStore
    @EnvironmentObject private var appNavigation: AppNavigationRouter
    @EnvironmentObject private var musicMatchesStore: MusicMatchesStore
    @EnvironmentObject private var messagesStore: MessagesStore
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var postsStore: PostsStore
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var playlistStore: PlaylistStore
    @EnvironmentObject private var emailVerification: EmailVerificationStore

    @State private var avatarImage: UIImage? = nil
    @State private var selectedTab: Int = 0
    @StateObject private var musicPlayer = MusicPlayer()
    @State private var showFullPlayer = false
    @State private var pendingTrackDetailFromPlayer: String?
    @State private var pendingProfileFromPlayer: String?
    @State private var trackDetailFromPlayer: TrackDetailPresentation?
    @State private var profileFromPlayer: ProfilePresentation?
    @Namespace private var zoomNamespace
    let coverID = "myZoomingCard"
    
    @available(iOS 26.1, *)
    fileprivate func ios26tabBar() -> some View {
        return TabView(selection: $selectedTab) {
            FeedView(isVisible: selectedTab == 0)
                .environmentObject(musicPlayer)
                .environmentObject(session)
                .tabItem { Image(systemName: "house.fill") }
                .tag(0)
            
            DiscoverView()
                .environmentObject(musicPlayer)
                .tabItem { Image(systemName: "safari.fill") }
                .tag(1)
            
            LibraryView()
                .tabItem { Image(systemName: "music.pages.fill") }
                .tag(2)
            
            InboxView()
                .environmentObject(musicPlayer)
                .environmentObject(session)
                .environmentObject(musicMatchesStore)
                .tabItem { Image(systemName: "tray.fill") }
                .tag(3)
            
            ProfileView()
                .environmentObject(session)
                .environmentObject(musicPlayer)
            .tabItem {
                if let avatar = avatarImage {
                    Image(uiImage: circularImage(avatar).withRenderingMode(.alwaysOriginal))
                } else {
                    Image(systemName: "person.crop.circle.fill")
                }
            }
            .tag(4)
        }
        .tint(Color.white)
        .tabBarMinimizeBehavior(selectedTab == 0 && musicPlayer.currentTrack == nil ? .never : .onScrollDown)
    }
    
    fileprivate func ios18tabBar() -> some View {
        return TabView(selection: $selectedTab) {
            ExampleView(exampleName: "Home")
                .tabItem { Image(systemName: "house.fill") }
                .tag(0)
            
            DiscoverView()
                .environmentObject(musicPlayer)
                .tabItem { Image(systemName: "safari.fill") }
                .tag(1)
            
            LibraryView()
                .tabItem { Image(systemName: "music.pages.fill") }
                .tag(2)
            
            ExampleView(exampleName: "Inbox")
                .tabItem { Image(systemName: "tray.fill") }
                .tag(3)
            
            ExampleView(exampleName: "Profile")
                .tabItem {
                    if let avatar = avatarImage {
                        Image(uiImage: circularImage(avatar).withRenderingMode(.alwaysOriginal))
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                    }
                }
                .tag(4)
        }
        .tint(Theme.accentColor)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            if #available(iOS 26.1, *) {
                ios26tabBar()
                    .environmentObject(musicPlayer)
                    .tabViewBottomAccessory(isEnabled: musicPlayer.currentTrack != nil) {
                        MiniPlayerView(showFullPlayer: $showFullPlayer)
                            .environmentObject(musicPlayer)
                            .environmentObject(musicStore)
                            .matchedTransitionSource(id: coverID, in: zoomNamespace)
                    }
            } else {
                ios18tabBar()
                    .environmentObject(musicPlayer)
                // add mini player above here
            }
        }
        .ignoresSafeArea(.all)
        .onChange(of: selectedTab) { _, tab in
            if tab != 0 {
                FeedPlayerCache.shared.stopAll()
            }
        }
        .onChange(of: appNavigation.selectedTab) { _, tab in
            guard let tab else { return }
            selectedTab = tab
            appNavigation.selectedTab = nil
        }
        .onAppear {
            loadAvatar()
        }
        .onChange(of: musicPlayer.currentTrack?.id) { _, _ in
            musicPlayer.enrichCurrentTrack(using: musicStore)
        }
        .task {
            musicMatchesStore.scheduleLaunchCheck()
        }
        .onChange(of: emailVerification.isPresented) { _, isPresented in
            if isPresented {
                musicPlayer.pauseAllPlayback()
                FeedPlayerCache.shared.stopAll()
            }
        }
        .sheet(isPresented: $showFullPlayer, onDismiss: {
            if let id = pendingTrackDetailFromPlayer {
                trackDetailFromPlayer = TrackDetailPresentation(id: id)
                pendingTrackDetailFromPlayer = nil
            }
            if let username = pendingProfileFromPlayer {
                profileFromPlayer = ProfilePresentation(username: username)
                pendingProfileFromPlayer = nil
            }
        }) {
            FullPlayerView(
                onOpenTrackDetail: { trackId in
                    pendingTrackDetailFromPlayer = trackId
                    showFullPlayer = false
                },
                onOpenProfile: { username in
                    pendingProfileFromPlayer = username
                    showFullPlayer = false
                }
            )
            .environmentObject(musicPlayer)
            .environmentObject(musicStore)
            .environmentObject(session)
            .environmentObject(appNavigation)
        }
        .fullScreenCover(item: $trackDetailFromPlayer) { presentation in
            TrackDetailFromPlayerCover(trackId: presentation.id)
                .environmentObject(musicStore)
                .environmentObject(musicPlayer)
                .environmentObject(session)
                .environmentObject(appNavigation)
        }
        .fullScreenCover(item: $profileFromPlayer) { presentation in
            ProfileFromPlayerCover(username: presentation.username)
                .environmentObject(session)
                .environmentObject(appNavigation)
        }
        .fullScreenCover(item: $appNavigation.modalPostRoute) { route in
            DeepLinkPostCover(postId: route.postId)
                .environmentObject(postsStore)
                .environmentObject(profileStore)
                .environmentObject(session)
                .environmentObject(musicPlayer)
                .environmentObject(appNavigation)
        }
        .fullScreenCover(item: $appNavigation.modalProfileRoute) { route in
            DeepLinkProfileCover(username: route.username)
                .environmentObject(appNavigation)
        }
        .fullScreenCover(item: $appNavigation.modalTrackDetailRoute) { route in
            DeepLinkTrackCover(reference: route.reference)
                .environmentObject(musicStore)
                .environmentObject(musicPlayer)
                .environmentObject(session)
                .environmentObject(appNavigation)
        }
        .fullScreenCover(item: $appNavigation.modalPlaylistRoute) { route in
            DeepLinkPlaylistCover(playlistId: route.playlistId)
                .environmentObject(playlistStore)
                .environmentObject(musicStore)
                .environmentObject(musicPlayer)
                .environmentObject(session)
                .environmentObject(appNavigation)
        }
        .fullScreenCover(item: $appNavigation.modalAppleArtistRoute) { route in
            DeepLinkAppleArtistCover(sourceId: route.sourceId)
                .environmentObject(appNavigation)
        }
        .fullScreenCover(item: $appNavigation.modalAppleAlbumRoute) { route in
            DeepLinkAppleAlbumCover(sourceId: route.sourceId)
                .environmentObject(appNavigation)
        }
        .fullScreenCover(item: $appNavigation.modalNicheAlbumRoute) { route in
            DeepLinkNicheAlbumCover(albumId: route.albumId)
                .environmentObject(musicStore)
                .environmentObject(musicPlayer)
                .environmentObject(session)
                .environmentObject(appNavigation)
        }
        .fullScreenCover(item: matchPresentationBinding) { match in
            MusicMatchFullscreenView(
                match: match,
                viewerAvatarURL: avatarLink(),
                store: musicMatchesStore,
                onOpenInbox: { selectedTab = 3 },
                onOpenConversation: { conversationId, otherUser in
                    selectedTab = 3
                    Task {
                        await messagesStore.openConversationFromMatch(
                            conversationId: conversationId,
                            recipient: MessageComposeRecipient(otherUser: otherUser)
                        )
                    }
                },
                onDismiss: { musicMatchesStore.clearPendingMatch() }
            )
        }
    }

    private var matchPresentationBinding: Binding<MusicMatch?> {
        Binding(
            get: { musicMatchesStore.pendingMatch },
            set: { newValue in
                if newValue == nil {
                    musicMatchesStore.clearPendingMatch()
                }
            }
        )
    }

    func loadAvatar() {
        guard let url = avatarLink() else { return }
        KingfisherManager.shared.retrieveImage(with: url) { result in
            if case .success(let value) = result {
                DispatchQueue.main.async {
                    avatarImage = value.image
                }
            }
        }
    }

    func circularImage(_ image: UIImage, size: CGFloat = 26) -> UIImage {
        let borderWidth: CGFloat = 1.5
        let total = size + borderWidth * 2
        let rect = CGRect(origin: .zero, size: CGSize(width: total, height: total))

        UIGraphicsBeginImageContextWithOptions(rect.size, false, UIScreen.main.scale)

        UIColor(white: 1, alpha: 0.2).setFill()
        UIBezierPath(ovalIn: rect).fill()

        let innerRect = rect.insetBy(dx: borderWidth, dy: borderWidth)
        UIBezierPath(ovalIn: innerRect).addClip()
        image.draw(in: innerRect)

        let result = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return result
    }

    private func avatarLink() -> URL? {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return URL(string: "https://cdn.nichemusic.app/avatars/cqXcxocvtYdEFnoDppneHg/avatar-cAZ-xSAdwUSalGao.jpg")
        }
        guard let urlString = session.currentUser?.avatarUrl else { return nil }
        return URL(string: urlString)
    }
}

private struct TrackDetailPresentation: Identifiable {
    let id: String
}

private struct ProfilePresentation: Identifiable {
    let username: String
    var id: String { username }
}

private struct TrackDetailFromPlayerCover: View {
    let trackId: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var musicStore: MusicStore
    @EnvironmentObject private var musicPlayer: MusicPlayer
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var appNavigation: AppNavigationRouter

    var body: some View {
        NavigationStack {
            NicheTrackDetailView(trackId: trackId)
                .environmentObject(musicStore)
                .environmentObject(musicPlayer)
                .environmentObject(session)
                .environmentObject(appNavigation)
                .sheetPresentationContainerDismiss { dismiss() }
                .externalNavigationDestinations()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                        }
                    }
                }
        }
    }
}

private struct ProfileFromPlayerCover: View {
    let username: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appNavigation: AppNavigationRouter

    var body: some View {
        NavigationStack {
            OtherProfileView(username: username)
                .toolbarVisibility(.hidden, for: .tabBar)
                .externalNavigationDestinations()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                        }
                    }
                }
        }
    }
}

private struct DeepLinkPostCover: View {
    let postId: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appNavigation: AppNavigationRouter

    var body: some View {
        NavigationStack {
            PostDetailView(postId: postId)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            appNavigation.modalPostRoute = nil
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                        }
                    }
                }
        }
    }
}

private struct DeepLinkProfileCover: View {
    let username: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appNavigation: AppNavigationRouter

    var body: some View {
        NavigationStack {
            OtherProfileView(username: username)
                .externalNavigationDestinations()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            appNavigation.modalProfileRoute = nil
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                        }
                    }
                }
        }
    }
}

private struct DeepLinkTrackCover: View {
    let reference: TrackDetailReference

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appNavigation: AppNavigationRouter

    var body: some View {
        NavigationStack {
            trackDetailDestination(reference)
                .externalNavigationDestinations()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            appNavigation.modalTrackDetailRoute = nil
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                        }
                    }
                }
        }
    }
}

private struct DeepLinkPlaylistCover: View {
    let playlistId: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appNavigation: AppNavigationRouter

    var body: some View {
        NavigationStack {
            PlaylistDetailView(playlistId: playlistId)
                .externalNavigationDestinations()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            appNavigation.modalPlaylistRoute = nil
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                        }
                    }
                }
        }
    }
}

private struct DeepLinkAppleArtistCover: View {
    let sourceId: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appNavigation: AppNavigationRouter

    var body: some View {
        NavigationStack {
            AppleArtistDetailView(sourceId: sourceId, ownerUsername: nil)
                .externalNavigationDestinations()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            appNavigation.modalAppleArtistRoute = nil
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                        }
                    }
                }
        }
    }
}

private struct DeepLinkAppleAlbumCover: View {
    let sourceId: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appNavigation: AppNavigationRouter

    var body: some View {
        NavigationStack {
            AppleAlbumDetailView(sourceId: sourceId)
                .externalNavigationDestinations()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            appNavigation.modalAppleAlbumRoute = nil
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                        }
                    }
                }
        }
    }
}

private struct DeepLinkNicheAlbumCover: View {
    let albumId: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appNavigation: AppNavigationRouter

    var body: some View {
        NavigationStack {
            NicheAlbumDetailView(albumId: albumId)
                .externalNavigationDestinations()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            appNavigation.modalNicheAlbumRoute = nil
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                        }
                    }
                }
        }
    }
}

struct ExampleView: View {
    let exampleName: String
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // A Header for the specific section
                    Text(exampleName)
                        .font(.system(size: 40, weight: .black))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 20)
                    
                    // A bunch of "Cards" to create scroll depth
                    ForEach(1...20, id: \.self) { index in
                        VStack(alignment: .leading) {
                            // Placeholder for a music/social post
                            RoundedRectangle(cornerRadius: 15)
                                .fill(LinearGradient(
                                    colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(height: 200)
                                .overlay(
                                    Image(systemName: "music.note.list")
                                        .font(.largeTitle)
                                        .foregroundColor(.white.opacity(0.2))
                                )
                            
                            Text("\(exampleName) Item #\(index)")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text("Subtitle or description text for the niche music scene.")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 100) // Extra space so we don't hit the tab bar immediately
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar(.hidden) // Hides nav bar so you can focus on tab bar behavior
        }
    }
}

#Preview("Main Tabs") {
    MainTabView()
        .environmentObject(
            SessionStore(
                bootstrap: false,
                previewState: .signedIn(.preview)
            )
        )
        .environmentObject(MusicStore.preview)
        .environmentObject(AppNavigationRouter())
        .environmentObject(MusicMatchesStore())
        .environmentObject(MessagesStore())
        .environmentObject(LibraryStore())
}
