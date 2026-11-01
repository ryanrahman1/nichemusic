//
//  DiscoverHomeSupport.swift
//  Niche Music
//

import Kingfisher
import SwiftUI

struct DiscoverHomeContent: View {
    @ObservedObject var store: DiscoverStore

    var body: some View {
        Group {
            if store.isLoading && store.home == nil {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.errorMessage, store.home == nil {
                discoverErrorView(error)
            } else if let home = store.home {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        if let spotlight = home.sections.artistSpotlight {
                            DiscoverSpotlightBanner(editorial: spotlight)
                                .padding(.horizontal, 16)
                        }

                        if !home.sections.forYou.isEmpty {
                            DiscoverTrackRail(title: "For You", tracks: home.sections.forYou)
                        }

                        if !home.sections.trendingNicheTracks.isEmpty {
                            DiscoverTrackRail(title: "Trending on Niche", tracks: home.sections.trendingNicheTracks)
                        }

                        if !home.sections.newNicheReleases.isEmpty {
                            DiscoverTrackRail(title: "New Releases", tracks: home.sections.newNicheReleases)
                        }

                        if !home.sections.featuredPlaylists.isEmpty {
                            DiscoverPlaylistRail(playlists: home.sections.featuredPlaylists)
                        }

                        if !home.sections.popularProfiles.isEmpty {
                            DiscoverProfileRail(profiles: home.sections.popularProfiles)
                        }

                        if !home.sections.recentPosts.isEmpty {
                            DiscoverRecentPostsSection(posts: home.sections.recentPosts)
                        }

                        if !home.sections.badgesCommunitiesChallenges.isEmpty {
                            DiscoverBadgeCommunityRail(items: home.sections.badgesCommunitiesChallenges)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 120)
                }
                .refreshable {
                    await store.refresh()
                }
            } else {
                discoverErrorView("Nothing to show yet.")
            }
        }
    }

    private func discoverErrorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Button("Try Again") {
                Task { await store.loadHome(force: true) }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DiscoverSpotlightBanner: View {
    let editorial: DiscoverEditorial

    @EnvironmentObject private var deepLinkCoordinator: DeepLinkCoordinator

    var body: some View {
        Button {
            if let link = editorial.link {
                deepLinkCoordinator.handleIncomingURLString(link)
            }
        } label: {
            bannerContent
        }
        .buttonStyle(.plain)
        .disabled(editorial.link == nil)
    }

    private var bannerContent: some View {
        ZStack(alignment: .bottomLeading) {
            artwork
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("Artist Spotlight")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))

                Text(editorial.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let subtitle = editorial.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                }
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = resolvedAppleArtworkURL(editorial.imageUrl, size: 720) {
            KFImage(url)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.accentColor.opacity(0.55), .white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
}

struct DiscoverTrackRail: View {
    let title: String
    let tracks: [DiscoverNicheTrack]

    var body: some View {
        LibraryHorizontalRail(title: title) {
            ForEach(tracks) { track in
                DiscoverNicheTrackCard(track: track)
            }
        }
    }
}

struct DiscoverNicheTrackCard: View {
    let track: DiscoverNicheTrack

    var body: some View {
        NavigationLink {
            NicheTrackDetailView(trackId: track.id)
                .toolbarVisibility(.hidden, for: .tabBar)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                artwork
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(track.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let artistName = track.displayArtistName {
                    Text(artistName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }
            }
            .frame(width: 132, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = resolvedAppleArtworkURL(track.artworkUrl, size: 260) {
            KFImage(url)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.white.opacity(0.35))
                }
        }
    }
}

struct DiscoverPlaylistRail: View {
    let playlists: [DiscoverPlaylist]

    var body: some View {
        LibraryHorizontalRail(title: "Featured Playlists") {
            ForEach(playlists) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlistId: playlist.id)
                        .toolbarVisibility(.hidden, for: .tabBar)
                } label: {
                    DiscoverPlaylistCard(playlist: playlist)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct DiscoverPlaylistCard: View {
    let playlist: DiscoverPlaylist

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            artwork
                .frame(width: 132, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(playlist.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(playlist.displaySubtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)
        }
        .frame(width: 132, alignment: .leading)
    }

    @ViewBuilder
    private var artwork: some View {
        if let imageUrl = playlist.imageUrl, let url = URL(string: imageUrl) {
            KFImage(url)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay {
                    Image(systemName: "music.note.list")
                        .foregroundStyle(.white.opacity(0.35))
                }
        }
    }
}

struct DiscoverProfileRail: View {
    let profiles: [DiscoverProfile]

    var body: some View {
        LibraryHorizontalRail(title: "Popular Creators") {
            ForEach(profiles) { profile in
                ProfileUsernameLink(username: profile.username) {
                    DiscoverProfileCard(profile: profile)
                }
            }
        }
    }
}

struct DiscoverProfileCard: View {
    let profile: DiscoverProfile

    var body: some View {
        VStack(spacing: 10) {
            avatar
                .frame(width: 96, height: 96)
                .clipShape(Circle())

            Text(profile.displayName ?? profile.username)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            if let followers = profile.followersCount {
                Text(followers == 1 ? "1 follower" : "\(followers) followers")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }
        }
        .frame(width: 108)
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarUrl = profile.avatarUrl, let url = URL(string: avatarUrl) {
            KFImage(url)
                .resizable()
                .scaledToFill()
        } else {
            Circle()
                .fill(.white.opacity(0.08))
                .overlay {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.white.opacity(0.35))
                }
        }
    }
}

struct DiscoverRecentPostsSection: View {
    let posts: [ProfilePost]

    @EnvironmentObject private var postsStore: PostsStore
    @Namespace private var postTransitionNamespace

    private var gridCellWidth: CGFloat { floor(UIScreen.main.bounds.width / 3) }
    private var gridCellHeight: CGFloat { gridCellWidth * 1.4 }
    private var gridHeight: CGFloat {
        CGFloat(ceil(Double(posts.count) / 3.0)) * gridCellHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LibrarySectionHeader(title: "Recent Posts")

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(gridCellWidth), spacing: 0),
                    count: 3
                ),
                spacing: 0
            ) {
                ForEach(posts) { post in
                    let gridPost = post.asPost

                    NavigationLink {
                        PostDetailView(postId: gridPost.id, initialPost: gridPost)
                            .navigationTransition(
                                .zoom(
                                    sourceID: gridPost.id,
                                    in: postTransitionNamespace
                                )
                            )
                            .toolbarVisibility(.hidden, for: .tabBar)
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
                        postsStore.mergePosts([gridPost])
                        gridPost.prefetchDetailMedia()
                    }
                }
            }
            .frame(height: gridHeight)
        }
    }
}

struct DiscoverBadgeCommunityRail: View {
    let items: [DiscoverBadgeCommunityItem]

    var body: some View {
        LibraryHorizontalRail(title: "Badges & Communities") {
            ForEach(items) { item in
                DiscoverBadgeCommunityCard(item: item)
            }
        }
    }
}

struct DiscoverBadgeCommunityCard: View {
    let item: DiscoverBadgeCommunityItem

    var body: some View {
        Group {
            if item.type == "badge", let preview = item.badgeDetailPreview {
                NavigationLink {
                    BadgeDetailView(badgeId: item.id, initialBadge: preview)
                } label: {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            artwork
                .frame(width: 132, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(item.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(item.displaySubtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)
        }
        .frame(width: 132, alignment: .leading)
    }

    @ViewBuilder
    private var artwork: some View {
        if item.type == "badge", let hex = item.colorHex, let color = Color.badgeHex(hex) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.85))
                .overlay {
                    Text(item.name.prefix(1).uppercased())
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                }
        } else if let imageUrl = item.imageUrl, let url = URL(string: imageUrl) {
            KFImage(url)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay {
                    Image(systemName: item.type == "community" ? "person.3.fill" : "rosette")
                        .foregroundStyle(.white.opacity(0.35))
                }
        }
    }
}
