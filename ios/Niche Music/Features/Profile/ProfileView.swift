//
//  ProfileView.swift
//  Niche Music
//
//  Created by Ryan Rahman on 5/24/26.
//


import SwiftUI
import Kingfisher

enum ProfileTab: String, CaseIterable {
    case posts = "Posts"
    case music = "Music"
    case reposts = "Reposts"
}

struct ProfileView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var postsStore: PostsStore
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var appNavigation: AppNavigationRouter
    @EnvironmentObject private var playlistStore: PlaylistStore
    
    @Namespace private var postTransitionNamespace
    
    
    @State private var selectedTab: ProfileTab = .posts
    @State private var isSettingsShown = false

    @Namespace private var tabNamespace

    private let heroHeight: CGFloat = 430

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundColor.ignoresSafeArea()

                if let user = profileStore.me {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            hero(user)

                            VStack(alignment: .leading, spacing: 26) {
                                identityBlock(user)
                                badgeRow(user)
                                profileSongSection(user)
                                profileActions(for: user)
                                tabSwitcher(user)
                                tabContent
                            }
                            .padding(.horizontal, 22)
                            .padding(.top, 24)
                            .padding(.bottom, 120)
                            .background(Theme.backgroundColor)
                        }
                    }
                    .coordinateSpace(name: "PROFILE_SCROLL")
                    .ignoresSafeArea(edges: .top)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                if let shareURL = URL(string: "https://share.nichemusic.app/user/\(user.username)") {
                                    ShareLink(item: shareURL) {
                                        Label("Share Profile", systemImage: "square.and.arrow.up")
                                    }
                                }

                                Button {
                                    isSettingsShown = true
                                } label: {
                                    Label("Settings", systemImage: "gearshape")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 38, height: 38)
                            }
                        }
                    }
                    .toolbarBackground(.hidden, for: .navigationBar)
                } else if profileStore.isInitialLoading {
                    NicheProgress()
                } else {
                    Text(profileStore.errorMessage ?? "Couldn’t load profile")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .toolbar(.visible, for: .tabBar)
        .onAppear {
            TabBarVisibility.setVisible(true)
        }
        .externalNavigationDestinations()
        .sheet(isPresented: $isSettingsShown) {
            NavigationStack {
                SettingsView()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task {
            await profileStore.loadMe()
            await profileStore.loadMyPosts()
        }
        .refreshable {
            await profileStore.loadMe(force: true)
            await profileStore.loadMyPosts(force: true)
            await profileStore.loadMyReposts(force: true)
            if profileStore.me?.isUserProfileType == true {
                await profileStore.loadMyMusic(force: true)
                await playlistStore.loadMyPlaylists(force: true)
            } else if profileStore.me?.isArtistProfileType == true {
                await profileStore.loadMyDiscography(filter: .all, force: true)
            }
        }
        .onChange(of: profileStore.myPosts) { _, posts in
            guard let posts else { return }
            postsStore.mergePosts(posts.posts.map { $0.asPost })
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .reposts {
                Task {
                    await profileStore.loadMyReposts()
                    cacheRepostsInPostsStore()
                }
            } else if tab == .music, profileStore.me?.isUserProfileType == true {
                Task {
                    await profileStore.loadMyMusic()
                    await playlistStore.loadMyPlaylists()
                }
            } else if tab == .music, profileStore.me?.isArtistProfileType == true {
                Task {
                    await profileStore.loadMyDiscography(filter: .all)
                }
            }
        }
        .onChange(of: profileStore.myReposts) { _, _ in
            cacheRepostsInPostsStore()
        }
    }

    private func cacheRepostsInPostsStore() {
        guard let reposts = profileStore.myReposts?.reposts else { return }
        postsStore.mergePosts(reposts.map { $0.post.asPost })
    }

    private func hero(_ user: FullUser) -> some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .named("PROFILE_SCROLL")).minY
            let pullDown = max(minY, 0)
            let height = heroHeight + pullDown

            ZStack(alignment: .bottomLeading) {
                if let avatarUrl = user.avatarUrl,
                   let url = URL(string: avatarUrl) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: height)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(.white.opacity(0.06))
                        .frame(width: geo.size.width, height: height)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 64, weight: .regular))
                                .foregroundStyle(.white.opacity(0.24))
                        }
                }

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.4), // Stays clear until 40% down the 190pt frame
                        .init(color: Theme.backgroundColor, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 190)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(width: geo.size.width, height: height)
            .offset(y: minY > 0 ? -minY : 0)
        }
        .ignoresSafeArea(edges: .top)
        .frame(height: heroHeight)
    }

    private func identityBlock(_ user: FullUser) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(user.displayName ?? user.username)
                .font(.system(size: 44, weight: .semibold))
                .tracking(-1.6)
                .foregroundStyle(.white)
                .lineLimit(2)

            Text(user.usernameWithTypeLine)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))

            HStack(spacing: 7) {
                NavigationLink {
                    ProfileConnectionsListView(kind: .followers)
                } label: {
                    Text("\(user.followersCount) followers")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                }
                .buttonStyle(.plain)

                Text("•")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))

                NavigationLink {
                    ProfileConnectionsListView(kind: .following)
                } label: {
                    Text("\(user.followingCount) following")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                }
                .buttonStyle(.plain)
            }

            if let bio = user.bio,
               !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(bio)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineSpacing(3)
                    .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private func badgeRow(_ user: FullUser) -> some View {
        let badges = user.sortedBadges
        if badges.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(badges) { profileBadge in
                        NavigationLink {
                            BadgeDetailView(
                                badgeId: profileBadge.id,
                                initialBadge: profileBadge.asBadgeDetail
                            )
                        } label: {
                            BadgePillView(text: profileBadge.text, colorHex: profileBadge.colorHex)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func profileSongSection(_ user: FullUser) -> some View {
        if let song = user.profileSong {
            profileSongRow(song)
        } else {
            profileSongEmptyRow
        }
    }

    private func profileSongRow(_ song: ProfileSong) -> some View {
        TrackDetailLink(reference: TrackDetailReference(song)) {
            HStack(spacing: 14) {
                Group {
                    if let artworkURL = song.resolvedArtworkURL {
                        KFImage(artworkURL)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.white.opacity(0.08)
                            .overlay {
                                Image(systemName: "music.note")
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Profile song")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.42))

                    Text(song.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(song.artist.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.28))
            }
            .padding(.vertical, 14)
            .overlay(alignment: .top) {
                Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
            }
        }
    }

    private var profileSongEmptyRow: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.white.opacity(0.45))
                }

            VStack(alignment: .leading, spacing: 5) {
                Text("Profile song")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))

                Text("Add a track that represents your sound.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
        }
    }

    private func profileActions(for user: FullUser) -> some View {
        HStack(spacing: 10) {
            NavigationLink {
                EditProfileView()
                    .environmentObject(profileStore)
                    .environmentObject(session)
            } label: {
                Text("Edit Profile")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            if let shareURL = URL(string: "https://share.nichemusic.app/user/\(user.username)") {
                ShareLink(item: shareURL) {
                    Text("Share")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
        }
    }

    private func tabSwitcher(_ user: FullUser) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                profileTabButton(.posts, count: user.postsCount)
                profileTabButton(.music, count: nil)
                profileTabButton(.reposts, count: nil)
            }

            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(height: 1)
        }
        .padding(.top, 4)
    }
    
    private func profileTabButton(_ tab: ProfileTab, count: Int?) -> some View {
        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 9) {
                HStack(spacing: 5) {
                    Text(tab.rawValue)
                        .font(.system(size: 15, weight: .semibold))

                    if let count {
                        Text("\(count)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selectedTab == tab ? .white.opacity(0.45) : .white.opacity(0.25))
                    }
                }
                .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.38))

                ZStack {
                    Rectangle()
                        .fill(.clear)
                        .frame(height: 2)

                    if selectedTab == tab {
                        Rectangle()
                            .fill(.white)
                            .frame(height: 2)
                            .matchedGeometryEffect(id: "profileTab", in: tabNamespace)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .posts:
            postsGrid

        case .music:
            if let user = profileStore.me, user.isUserProfileType {
                ProfileUserMusicTabView(scope: .ownProfile)
            } else if profileStore.me?.isArtistProfileType == true {
                ProfileArtistDiscographyTabView(scope: .ownProfile)
            } else {
                musicPreview
            }

        case .reposts:
            repostsGrid
        }
    }

    private var repostPosts: [Post] {
        profileStore.myReposts?.reposts.map { $0.post.asPost } ?? []
    }

    private var repostsGrid: some View {
        VStack(spacing: 0) {
            if profileStore.isLoadingReposts && repostPosts.isEmpty {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else if repostPosts.isEmpty {
                editorialEmptyState(
                    title: "Reposts",
                    body: "Posts you repost will show up here."
                )
            } else {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(gridCellWidth), spacing: 0),
                        count: 3
                    ),
                    spacing: 0
                ) {
                    ForEach(profileStore.myReposts?.reposts ?? []) { repost in
                        let post = repost.post.asPost

                        NavigationLink {
                            PostDetailView(postId: post.id, initialPost: post)
                                .navigationTransition(
                                    .zoom(
                                        sourceID: post.id,
                                        in: postTransitionNamespace
                                    )
                                )
                        } label: {
                            PostGridCell(
                                post: post,
                                width: gridCellWidth,
                                height: gridCellHeight
                            )
                            .matchedTransitionSource(
                                id: post.id,
                                in: postTransitionNamespace
                            )
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            // postsStore.mergePosts already called in bulk by onChange(of: profileStore.myReposts)
                            post.prefetchDetailMedia()
                            Task {
                                await profileStore.loadMoreMyRepostsIfNeeded(currentRepost: repost)
                            }
                        }
                    }
                }
                .frame(height: repostsGridHeight)
                .padding(.horizontal, -22)
            }
        }
    }

    private var repostsGridHeight: CGFloat {
        CGFloat(ceil(Double(repostPosts.count) / 3.0)) * gridCellHeight
    }

    private var myProfilePosts: [ProfilePost] {
        profileStore.myPosts?.posts ?? []
    }

    // Pre-computed once — screen width never changes during a scroll session.
    private var gridCellWidth: CGFloat { floor(UIScreen.main.bounds.width / 3) }
    private var gridCellHeight: CGFloat { gridCellWidth * 1.4 }

    private var postsGrid: some View {
        VStack(spacing: 0) {
            if profileStore.isLoadingPosts && myProfilePosts.isEmpty {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else if myProfilePosts.isEmpty {
                editorialEmptyState(
                    title: "Posts",
                    body: "Posts will show up here."
                )
            } else {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(gridCellWidth), spacing: 0),
                        count: 3
                    ),
                    spacing: 0
                ) {
                    ForEach(myProfilePosts) { post in
                        let gridPost = post.asPost

                        NavigationLink {
                            PostDetailView(postId: gridPost.id, initialPost: gridPost)
                                .navigationTransition(
                                    .zoom(
                                        sourceID: gridPost.id,
                                        in: postTransitionNamespace
                                    )
                                )
                        } label: {
                            PostGridCell(
                                post: gridPost,
                                width: gridCellWidth,
                                height: gridCellHeight
                            )
                            .matchedTransitionSource(
                                id: gridPost.id,
                                in: postTransitionNamespace
                            )
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            // postsStore.mergePosts already called in bulk by onChange(of: profileStore.myPosts)
                            gridPost.prefetchDetailMedia()
                            Task {
                                await profileStore.loadMoreMyPostsIfNeeded(currentPost: post)
                            }
                        }
                    }
                }
                .frame(height: gridHeight)
                .padding(.horizontal, -22)
            }
        }
    }

    private var gridHeight: CGFloat {
        CGFloat(ceil(Double(myProfilePosts.count) / 3.0)) * gridCellHeight
    }

    private var musicPreview: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Music")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(.white)

            VStack(spacing: 0) {
                musicRow(title: "Uploaded Tracks", subtitle: "Original music released on Niche.")
                musicRow(title: "Saved Tracks", subtitle: "Songs this user keeps coming back to.")
                musicRow(title: "Playlists", subtitle: "Collections built around sound and mood.")
                musicRow(title: "Liked Artists", subtitle: "Artists shaping this profile’s taste.")
            }
        }
    }

    private func musicRow(title: String, subtitle: String) -> some View {
        row(title: title, subtitle: subtitle, icon: "music.note")
    }

    private func communityRow(title: String, subtitle: String) -> some View {
        row(title: title, subtitle: subtitle, icon: "person.2")
    }

    private func row(title: String, subtitle: String, icon: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.white.opacity(0.45))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.32))
            }
            .padding(.vertical, 18)

            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)
        }
    }

    private func editorialEmptyState(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(.white)

            Text(body)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white.opacity(0.48))
                .lineSpacing(3)

            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)
                .padding(.top, 14)
        }
    }
}

private extension Color {
    init?(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") {
            sanitized.removeFirst()
        }

        guard sanitized.count == 6,
              let value = UInt64(sanitized, radix: 16) else {
            return nil
        }

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

#Preview {
    ProfileView()
        .environmentObject(ProfileStore.preview)
        .environmentObject(PostsStore())
        .environmentObject(PlaylistStore())
        .environmentObject(
            SessionStore(
                bootstrap: false,
                previewState: .signedIn(.preview)
            )
        )
}
