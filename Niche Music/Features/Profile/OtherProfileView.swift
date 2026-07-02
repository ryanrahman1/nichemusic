//
//  OtherProfileView.swift
//  Niche Music
//
//  Created by Ryan Rahman on 6/2/26.
//

import SwiftUI
import Kingfisher

struct OtherProfileView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var postsStore: PostsStore
    @EnvironmentObject private var messagesStore: MessagesStore
    @EnvironmentObject private var playlistStore: PlaylistStore

    let username: String

    @Namespace private var postTransitionNamespace
    @State private var selectedTab: ProfileTab = .posts
    @State private var messageComposeNavigation: MessageComposeIntent?
    @State private var showBlockConfirm = false
    @State private var showUnblockConfirm = false
    @State private var isBlockActionInFlight = false
    @State private var blockActionError: String?
    @Namespace private var tabNamespace

    private let heroHeight: CGFloat = 430

    private var profileData: OtherProfileData? {
        profileStore.otherProfile(for: username)
    }

    private var user: FullUser? {
        profileData?.user
    }

    private var viewer: ProfileViewerContext? {
        profileData?.user != nil ? profileData?.viewer : nil
    }

    private var isPrivateTeaser: Bool {
        guard let user, user.isPrivate else { return false }
        if viewer?.isSelf == true { return false }
        return viewer?.isFollowing != true
    }

    private var isFollowActionInFlight: Bool {
        profileStore.followActionUsernames.contains(normalizedUsername)
    }

    private var normalizedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()

            if let user {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        hero(user)

                        VStack(alignment: .leading, spacing: 26) {
                            identityBlock(user)

                            if isPrivateTeaser {
                                privateAccountNotice
                            } else {
                                badgeRow(user)
                                profileSongSection(user)
                                profileActions
                                tabSwitcher(user)
                                tabContent
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 24)
                        .padding(.bottom, 120)
                        .background(Theme.backgroundColor)
                    }
                }
                .coordinateSpace(name: "OTHER_PROFILE_SCROLL")
                .ignoresSafeArea(edges: .top)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 8) {
                            if viewer?.isSelf != true {
                                Menu {
                                    if viewer?.isBlocked == true {
                                        Button("Unblock @\(user.username)") {
                                            showUnblockConfirm = true
                                        }
                                    } else {
                                        Button("Block @\(user.username)", role: .destructive) {
                                            showBlockConfirm = true
                                        }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 19, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 38, height: 38)
                                }
                                .disabled(isBlockActionInFlight)
                            }

                            if let shareURL = URL(string: "https://share.nichemusic.app/user/\(user.username)") {
                                ShareLink(item: shareURL) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 19, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 38, height: 38)
                                }
                            }
                        }
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
            } else if profileStore.isLoadingOtherProfile(username) {
                NicheProgress()
            } else {
                VStack(spacing: 14) {
                    Text(profileData?.errorMessage ?? "Couldn't load profile")
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)

                    Button("Try again") {
                        Task { await profileStore.loadUser(username: username, force: true) }
                    }
                    .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $messageComposeNavigation) { intent in
            MessageComposeView(
                initialRecipient: intent.recipient,
                initialConversationId: intent.conversationId
            )
            .environmentObject(messagesStore)
            .toolbarVisibility(.hidden, for: .tabBar)
        }
        .task {
            await profileStore.loadUser(username: username)
            if !isPrivateTeaser {
                await profileStore.loadUserPosts(username: username)
            }
        }
        .refreshable {
            await profileStore.loadUser(username: username, force: true)
            if !isPrivateTeaser {
                await profileStore.loadUserPosts(username: username, force: true)
                await profileStore.loadUserReposts(username: username, force: true)
                if user?.isUserProfileType == true {
                    await profileStore.loadUserMusic(username: username, force: true)
                    await playlistStore.loadUserPlaylists(username: username, force: true)
                } else if user?.isArtistProfileType == true {
                    await profileStore.loadUserDiscography(username: username, filter: .all, force: true)
                }
            }
        }
        .onChange(of: selectedTab) { _, tab in
            guard !isPrivateTeaser else { return }
            if tab == .reposts {
                Task {
                    await profileStore.loadUserReposts(username: username)
                    cacheRepostsInPostsStore()
                }
            } else if tab == .music, user?.isUserProfileType == true {
                Task {
                    await profileStore.loadUserMusic(username: username)
                    await playlistStore.loadUserPlaylists(username: username)
                }
            } else if tab == .music, user?.isArtistProfileType == true {
                Task {
                    await profileStore.loadUserDiscography(username: username, filter: .all)
                }
            }
        }
        .onChange(of: profileData?.reposts) { _, _ in
            cacheRepostsInPostsStore()
        }
        .onChange(of: profileData?.posts) { _, posts in
            guard let posts else { return }
            postsStore.mergePosts(posts.posts.map { $0.asPost })
        }
        .onChange(of: profileData?.viewer?.isFollowing) { _, isFollowing in
            guard isFollowing == true else { return }
            Task {
                await profileStore.loadUserPosts(username: username)
            }
        }
        .confirmationDialog(
            "Block @\(username)?",
            isPresented: $showBlockConfirm,
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                Task { await performBlock() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They won't be able to find your profile or see your posts. You won't see them either.")
        }
        .confirmationDialog(
            "Unblock @\(username)?",
            isPresented: $showUnblockConfirm,
            titleVisibility: .visible
        ) {
            Button("Unblock") {
                Task { await performUnblock() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Couldn't update block", isPresented: Binding(
            get: { blockActionError != nil },
            set: { if !$0 { blockActionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(blockActionError ?? "")
        }
    }

    private func performBlock() async {
        isBlockActionInFlight = true
        defer { isBlockActionInFlight = false }

        do {
            try await profileStore.blockUser(username: username)
        } catch {
            blockActionError = error.localizedDescription
        }
    }

    private func performUnblock() async {
        isBlockActionInFlight = true
        defer { isBlockActionInFlight = false }

        do {
            try await profileStore.unblockUser(username: username)
        } catch {
            blockActionError = error.localizedDescription
        }
    }

    private var privateAccountNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This account is private")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(.white)

            Text("Follow this account to see their posts, reposts, and music.")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white.opacity(0.48))
                .lineSpacing(3)

            if viewer?.isSelf != true {
                profileActions
            }
        }
    }

    private func cacheRepostsInPostsStore() {
        guard let reposts = profileData?.reposts?.reposts else { return }
        postsStore.mergePosts(reposts.map { $0.post.asPost })
    }

    private func hero(_ user: FullUser) -> some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .named("OTHER_PROFILE_SCROLL")).minY
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
                        .init(color: .clear, location: 0.4),
                        .init(color: Theme.backgroundColor.opacity(0.72), location: 0.8),
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
            HStack(spacing: 8) {
                Text(user.displayName ?? user.username)
                    .font(.system(size: 44, weight: .semibold))
                    .tracking(-1.6)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if user.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }

            Text(user.usernameWithTypeLine)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))

            HStack(spacing: 7) {
                NavigationLink {
                    ProfileConnectionsListView(kind: .followers, username: user.username)
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
                    ProfileConnectionsListView(kind: .following, username: user.username)
                } label: {
                    Text("\(user.followingCount) following")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                }
                .buttonStyle(.plain)
            }

            if let bio = user.bio,
               !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !isPrivateTeaser {
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

    private var profileActions: some View {
        HStack(spacing: 10) {
            if viewer?.isSelf != true {
                Button {
                    Task { await profileStore.toggleFollow(username: username) }
                } label: {
                    Text(followButtonTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isFollowActionInFlight)
                .opacity(isFollowActionInFlight ? 0.6 : 1)
            }

            if viewer?.isSelf != true, let user, viewer?.isBlocked != true {
                Button {
                    messageComposeNavigation = MessageComposeIntent(
                        recipient: MessageComposeRecipient(profile: user),
                        conversationId: nil
                    )
                } label: {
                    Text("Message")
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

    private var followButtonTitle: String {
        guard let viewer else { return "Follow" }
        if viewer.isFollowing == true { return "Following" }
        if viewer.outgoingFollowRequest { return "Requested" }
        return "Follow"
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
                            .matchedGeometryEffect(id: "otherProfileTab", in: tabNamespace)
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
            if let user, user.isUserProfileType {
                ProfileUserMusicTabView(scope: .user(username: user.username))
            } else if let user, user.isArtistProfileType {
                ProfileArtistDiscographyTabView(scope: .user(username: user.username))
            } else {
                musicPreview
            }
        case .reposts:
            repostsGrid
        }
    }

    private var userPosts: [ProfilePost] {
        profileData?.posts?.posts ?? []
    }

    private var repostPosts: [Post] {
        profileData?.reposts?.reposts.map { $0.post.asPost } ?? []
    }

    private var repostsGrid: some View {
        VStack(spacing: 0) {
            if profileStore.otherRepostsLoadingUsernames.contains(normalizedUsername) && repostPosts.isEmpty {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else if repostPosts.isEmpty {
                editorialEmptyState(
                    title: "Reposts",
                    body: "Posts this user reposts will show up here."
                )
            } else {
                GeometryReader { geo in
                    let cellWidth = floor(geo.size.width / 3)
                    let cellHeight = cellWidth * 1.4

                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.fixed(cellWidth), spacing: 0),
                            count: 3
                        ),
                        spacing: 0
                    ) {
                        ForEach(profileData?.reposts?.reposts ?? []) { repost in
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
                                    width: cellWidth,
                                    height: cellHeight
                                )
                                .matchedTransitionSource(
                                    id: post.id,
                                    in: postTransitionNamespace
                                )
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                postsStore.mergePosts([post])
                                post.prefetchDetailMedia()
                                Task {
                                    await profileStore.loadMoreUserRepostsIfNeeded(
                                        username: username,
                                        currentRepost: repost
                                    )
                                }
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
        let rows = ceil(Double(repostPosts.count) / 3.0)
        let screenWidth = UIScreen.main.bounds.width
        let cellWidth = floor(screenWidth / 3)
        let cellHeight = cellWidth * 1.4
        return CGFloat(rows) * cellHeight
    }

    private var postsGrid: some View {
        VStack(spacing: 0) {
            if profileStore.otherPostsLoadingUsernames.contains(normalizedUsername) && userPosts.isEmpty {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else if userPosts.isEmpty {
                editorialEmptyState(
                    title: "Posts",
                    body: "Posts will show up here."
                )
            } else {
                GeometryReader { geo in
                    let cellWidth = floor(geo.size.width / 3)
                    let cellHeight = cellWidth * 1.4

                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.fixed(cellWidth), spacing: 0),
                            count: 3
                        ),
                        spacing: 0
                    ) {
                        ForEach(userPosts) { post in
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
                                    width: cellWidth,
                                    height: cellHeight
                                )
                                .matchedTransitionSource(
                                    id: gridPost.id,
                                    in: postTransitionNamespace
                                )
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                postsStore.mergePosts([gridPost])
                                gridPost.prefetchDetailMedia()
                                Task {
                                    await profileStore.loadMoreUserPostsIfNeeded(
                                        username: username,
                                        currentPost: post
                                    )
                                }
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
        let rows = ceil(Double(userPosts.count) / 3.0)
        let screenWidth = UIScreen.main.bounds.width
        let cellWidth = floor(screenWidth / 3)
        let cellHeight = cellWidth * 1.4
        return CGFloat(rows) * cellHeight
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
                musicRow(title: "Liked Artists", subtitle: "Artists shaping this profile's taste.")
            }
        }
    }

    private func musicRow(title: String, subtitle: String) -> some View {
        row(title: title, subtitle: subtitle, icon: "music.note")
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
    NavigationStack {
        OtherProfileView(username: "ryanr")
            .environmentObject(ProfileStore.preview)
            .environmentObject(PostsStore())
    }
}
