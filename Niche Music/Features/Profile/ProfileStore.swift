//
//  ProfileStore.swift
//  nichemusic
//
//  Created by Ryan Rahman on 4/25/26.
//

import Foundation
import Combine

@MainActor
final class ProfileStore: ObservableObject {
    @Published var me: FullUser?
    @Published var isInitialLoading = false
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var myPosts: ProfilePosts?
    @Published var myReposts: ProfileReposts?
    @Published var likedTracks: [LibraryTrack] = []
    @Published var likedSongs: [ProfileMusicSong] = []
    @Published var savedAlbums: [LibraryAlbum] = []
    @Published var savedSongs: [ProfileMusicSong] = []
    @Published var followingArtists: [LibraryArtist] = []
    @Published var followingArtistProfiles: [ProfileFollowingArtist] = []
    @Published private(set) var myDiscographyByFilter: [String: ProfileDiscographyCollection] = [:]
    
    @Published var isLoadingPosts = false
    @Published var isLoadingMorePosts = false
    @Published var isLoadingReposts = false
    @Published var isLoadingMoreReposts = false
    @Published var isLoadingMusic = false
    @Published var isRefreshingMusic = false
    @Published var isLoadingDiscography = false
    @Published var isRefreshingDiscography = false
    @Published var isLoadingMoreDiscography = false
    @Published var isLoadingMoreLikedTracks = false
    @Published var isLoadingMoreSavedAlbums = false
    @Published var isLoadingMoreFollowingArtists = false

    private var meLastLoadedAt: Date?
    private let meTtl: TimeInterval = 180 // 3 minutes
    
    private var postsLastLoadedAt: Date?
    private let postsTtl: TimeInterval = 120 // 2 minutes
    private let postsPageSize = 20
    private var postsPagesByRequestCursor: [String: ProfilePostsPage] = [:]
    private var postsRequestCursorOrder: [String] = []
    private var repostsLastLoadedAt: Date?
    private let repostsTtl: TimeInterval = 120 // 2 minutes
    private let repostsPageSize = 20
    private var repostPagesByRequestCursor: [String: ProfileRepostsPage] = [:]
    private var repostRequestCursorOrder: [String] = []
    private var musicLastLoadedAt: Date?
    private let musicTtl: TimeInterval = 180 // 3 minutes
    private let musicPageSize = 20
    private var likedSongsPagesByRequestCursor: [String: ProfileMusicSongPage] = [:]
    private var likedSongsRequestCursorOrder: [String] = []
    private var savedSongsPagesByRequestCursor: [String: ProfileMusicSongPage] = [:]
    private var savedSongsRequestCursorOrder: [String] = []
    private var followingArtistsPagesByRequestCursor: [String: ProfileFollowingArtistPage] = [:]
    private var followingArtistsRequestCursorOrder: [String] = []
    private var likedSongsHasMore = false
    private var likedSongsNextCursor: String?
    private var savedSongsHasMore = false
    private var savedSongsNextCursor: String?
    private var followingArtistsHasMore = false
    private var followingArtistsNextCursor: String?

    private var discographyLastLoadedAt: Date?
    private let discographyPageSize = 20
    private var myDiscographyPagesByFilter: [String: [String: ProfileDiscographyPage]] = [:]
    private var myDiscographyCursorOrderByFilter: [String: [String]] = [:]
    private var otherDiscographyPagesByUsername: [String: [String: [String: ProfileDiscographyPage]]] = [:]
    private var otherDiscographyCursorOrderByUsername: [String: [String: [String]]] = [:]

    @Published private(set) var otherProfiles: [String: OtherProfileData] = [:]
    @Published private(set) var otherProfileLoadingUsernames: Set<String> = []
    @Published private(set) var otherPostsLoadingUsernames: Set<String> = []
    @Published private(set) var otherRepostsLoadingUsernames: Set<String> = []
    @Published private(set) var otherMusicLoadingUsernames: Set<String> = []
    @Published private(set) var otherDiscographyLoadingUsernames: Set<String> = []
    @Published private(set) var followActionUsernames: Set<String> = []

    private var otherPostsPagesByUsername: [String: [String: ProfilePostsPage]] = [:]
    private var otherPostsCursorOrderByUsername: [String: [String]] = [:]
    private var otherRepostsPagesByUsername: [String: [String: ProfileRepostsPage]] = [:]
    private var otherRepostsCursorOrderByUsername: [String: [String]] = [:]

    func otherProfile(for username: String) -> OtherProfileData? {
        otherProfiles[normalizeUsername(username)]
    }

    func isLoadingOtherProfile(_ username: String) -> Bool {
        otherProfileLoadingUsernames.contains(normalizeUsername(username))
    }

    func loadUser(username: String, force: Bool = false) async {
        let key = normalizeUsername(username)
        if otherProfileLoadingUsernames.contains(key) { return }

        let cached = otherProfiles[key]
        if !force,
           let cached,
           let profileLoadedAt = cached.profileLoadedAt,
           cached.user != nil,
           Date().timeIntervalSince(profileLoadedAt) < meTtl {
            return
        }

        otherProfileLoadingUsernames.insert(key)
        var data = otherProfiles[key] ?? OtherProfileData()
        data.errorMessage = nil
        otherProfiles[key] = data

        defer { otherProfileLoadingUsernames.remove(key) }

        do {
            let response: UserProfileResponse = try await APIClient.shared.request(
                Endpoints.user(username: username),
                method: .get
            )

            let resolvedKey = normalizeUsername(response.user.username)
            var updated = otherProfiles[resolvedKey] ?? OtherProfileData()
            updated.user = response.user
            updated.viewer = response.viewer
            updated.profileLoadedAt = Date()
            updated.errorMessage = nil
            otherProfiles[resolvedKey] = updated
        } catch {
            var failed = otherProfiles[key] ?? OtherProfileData()
            failed.errorMessage = error.localizedDescription
            otherProfiles[key] = failed
        }
    }

    func loadUserPosts(username: String, force: Bool = false) async {
        let key = normalizeUsername(username)
        if otherPostsLoadingUsernames.contains(key) { return }

        let cached = otherProfiles[key]
        if !force,
           cached?.posts != nil,
           let postsLoadedAt = cached?.postsLoadedAt,
           Date().timeIntervalSince(postsLoadedAt) < postsTtl {
            return
        }

        otherPostsLoadingUsernames.insert(key)

        defer { otherPostsLoadingUsernames.remove(key) }

        do {
            let firstPage = try await fetchUserPostsPage(username: username, requestCursor: nil)
            otherPostsPagesByUsername[key] = [cursorKey(for: nil): firstPage]
            otherPostsCursorOrderByUsername[key] = [cursorKey(for: nil)]
            publishOtherPostsFromCachedPages(username: username)
        } catch {
            var data = otherProfiles[key] ?? OtherProfileData()
            data.errorMessage = error.localizedDescription
            otherProfiles[key] = data
        }
    }

    func loadMoreUserPosts(username: String) async {
        let key = normalizeUsername(username)
        guard let current = otherProfiles[key]?.posts, current.hasMore else { return }
        guard let nextCursor = current.nextCursor else { return }
        if otherPostsLoadingUsernames.contains(key) { return }

        let nextCursorKey = cursorKey(for: nextCursor)
        if otherPostsPagesByUsername[key]?[nextCursorKey] != nil {
            appendOtherPostsRequestCursorIfNeeded(username: username, cursorKey: nextCursorKey)
            publishOtherPostsFromCachedPages(username: username)
            return
        }

        otherPostsLoadingUsernames.insert(key)

        defer { otherPostsLoadingUsernames.remove(key) }

        do {
            let nextPage = try await fetchUserPostsPage(username: username, requestCursor: nextCursor)
            var pages = otherPostsPagesByUsername[key] ?? [:]
            pages[nextCursorKey] = nextPage
            otherPostsPagesByUsername[key] = pages
            appendOtherPostsRequestCursorIfNeeded(username: username, cursorKey: nextCursorKey)
            publishOtherPostsFromCachedPages(username: username)
        } catch {
            var data = otherProfiles[key] ?? OtherProfileData()
            data.errorMessage = error.localizedDescription
            otherProfiles[key] = data
        }
    }

    func loadMoreUserPostsIfNeeded(username: String, currentPost: ProfilePost?) async {
        guard let currentPost,
              let current = otherProfiles[normalizeUsername(username)]?.posts else { return }
        guard current.hasMore, !otherPostsLoadingUsernames.contains(normalizeUsername(username)) else { return }

        let posts = current.posts
        let threshold = posts.index(posts.endIndex, offsetBy: -4, limitedBy: posts.startIndex) ?? posts.startIndex

        guard let index = posts.firstIndex(where: { $0.id == currentPost.id }),
              index >= threshold else {
            return
        }

        await loadMoreUserPosts(username: username)
    }

    func loadUserReposts(username: String, force: Bool = false) async {
        let key = normalizeUsername(username)
        if otherRepostsLoadingUsernames.contains(key) { return }

        let cached = otherProfiles[key]
        if !force,
           cached?.reposts != nil,
           let repostsLoadedAt = cached?.repostsLoadedAt,
           Date().timeIntervalSince(repostsLoadedAt) < repostsTtl {
            return
        }

        otherRepostsLoadingUsernames.insert(key)

        defer { otherRepostsLoadingUsernames.remove(key) }

        do {
            let firstPage = try await fetchUserRepostsPage(username: username, requestCursor: nil)
            otherRepostsPagesByUsername[key] = [cursorKey(for: nil): firstPage]
            otherRepostsCursorOrderByUsername[key] = [cursorKey(for: nil)]
            publishOtherRepostsFromCachedPages(username: username)
        } catch {
            var data = otherProfiles[key] ?? OtherProfileData()
            data.errorMessage = error.localizedDescription
            otherProfiles[key] = data
        }
    }

    func loadMoreUserReposts(username: String) async {
        let key = normalizeUsername(username)
        guard let current = otherProfiles[key]?.reposts, current.hasMore else { return }
        guard let nextCursor = current.nextCursor else { return }
        if otherRepostsLoadingUsernames.contains(key) { return }

        let nextCursorKey = cursorKey(for: nextCursor)
        if otherRepostsPagesByUsername[key]?[nextCursorKey] != nil {
            appendOtherRepostsRequestCursorIfNeeded(username: username, cursorKey: nextCursorKey)
            publishOtherRepostsFromCachedPages(username: username)
            return
        }

        otherRepostsLoadingUsernames.insert(key)

        defer { otherRepostsLoadingUsernames.remove(key) }

        do {
            let nextPage = try await fetchUserRepostsPage(username: username, requestCursor: nextCursor)
            var pages = otherRepostsPagesByUsername[key] ?? [:]
            pages[nextCursorKey] = nextPage
            otherRepostsPagesByUsername[key] = pages
            appendOtherRepostsRequestCursorIfNeeded(username: username, cursorKey: nextCursorKey)
            publishOtherRepostsFromCachedPages(username: username)
        } catch {
            var data = otherProfiles[key] ?? OtherProfileData()
            data.errorMessage = error.localizedDescription
            otherProfiles[key] = data
        }
    }

    func loadMoreUserRepostsIfNeeded(username: String, currentRepost: ProfileRepost?) async {
        guard let currentRepost,
              let current = otherProfiles[normalizeUsername(username)]?.reposts else { return }
        guard current.hasMore, !otherRepostsLoadingUsernames.contains(normalizeUsername(username)) else { return }

        let reposts = current.reposts
        let threshold = reposts.index(reposts.endIndex, offsetBy: -4, limitedBy: reposts.startIndex) ?? reposts.startIndex

        guard let index = reposts.firstIndex(where: { $0.id == currentRepost.id }),
              index >= threshold else {
            return
        }

        await loadMoreUserReposts(username: username)
    }

    func toggleFollow(username: String) async {
        let key = normalizeUsername(username)
        guard !followActionUsernames.contains(key) else { return }

        let viewer = otherProfiles[key]?.viewer
        let isFollowing = viewer?.isFollowing == true
        let hasOutgoingRequest = viewer?.outgoingFollowRequest == true

        followActionUsernames.insert(key)
        defer { followActionUsernames.remove(key) }

        do {
            if isFollowing || hasOutgoingRequest {
                try await APIClient.shared.requestVoid(
                    Endpoints.unfollowUser(username: username),
                    method: .post
                )
            } else {
                try await APIClient.shared.requestVoid(
                    Endpoints.followUser(username: username),
                    method: .post
                )
            }

            await loadUser(username: username, force: true)
        } catch {
            var data = otherProfiles[key] ?? OtherProfileData()
            data.errorMessage = error.localizedDescription
            otherProfiles[key] = data
        }
    }

    func blockUser(username: String) async throws {
        let key = normalizeUsername(username)
        try await APIClient.shared.requestVoid(
            Endpoints.blockUser(username: username),
            method: .post
        )
        otherProfiles.removeValue(forKey: key)
    }

    func unblockUser(username: String) async throws {
        let key = normalizeUsername(username)
        try await APIClient.shared.requestVoid(
            Endpoints.unblockUser(username: username),
            method: .post
        )
        await loadUser(username: username, force: true)
    }

    func acceptFollowRequest(userId: String) async throws {
        try await APIClient.shared.requestVoid(
            Endpoints.acceptFollowRequest(userId: userId),
            method: .post
        )
    }

    func rejectFollowRequest(userId: String) async throws {
        try await APIClient.shared.requestVoid(
            Endpoints.rejectFollowRequest(userId: userId),
            method: .post
        )
    }

    func removePostFromCaches(postId: String) {
        if let posts = myPosts {
            myPosts = ProfilePosts(
                posts: posts.posts.filter { $0.id != postId },
                nextCursor: posts.nextCursor,
                hasMore: posts.hasMore,
                limit: posts.limit
            )
        }

        for username in otherProfiles.keys {
            guard var data = otherProfiles[username],
                  let posts = data.posts else { continue }
            let filtered = posts.posts.filter { $0.id != postId }
            if filtered.count != posts.posts.count {
                data.posts = ProfilePosts(
                    posts: filtered,
                    nextCursor: posts.nextCursor,
                    hasMore: posts.hasMore,
                    limit: posts.limit
                )
                otherProfiles[username] = data
            }
        }
    }

    func loadMe(force: Bool = false) async {
        if isRefreshing || isInitialLoading { return }

        let hasCachedData = me != nil

        if !force,
           hasCachedData,
           let meLastLoadedAt,
           Date().timeIntervalSince(meLastLoadedAt) < meTtl {
            return
        }

        if hasCachedData {
            isRefreshing = true
        } else {
            isInitialLoading = true
        }

        errorMessage = nil

        defer {
            isInitialLoading = false
            isRefreshing = false
        }

        do {
            let response: MeResponse = try await APIClient.shared.request(
                Endpoints.me,
                method: .get
            )

            me = response.user
            meLastLoadedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func loadMyPosts(force: Bool = false) async {
        if isRefreshing || isLoadingPosts || isLoadingMorePosts { return }
        let hasCachedData = myPosts != nil
        let isFresh: Bool = {
            guard !force,
                  hasCachedData,
                  let postsLastLoadedAt else {
                return false
            }

            return Date().timeIntervalSince(postsLastLoadedAt) < postsTtl
        }()

        if isFresh {
            return
        }
        
        if hasCachedData {
            isRefreshing = true
        } else {
            isLoadingPosts = true
        }
        
        errorMessage = nil
        
        do {
            let firstPage = try await fetchPostsPage(requestCursor: nil)
            postsPagesByRequestCursor = [cursorKey(for: nil): firstPage]
            postsRequestCursorOrder = [cursorKey(for: nil)]
            publishPostsFromCachedPages()
            postsLastLoadedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoadingPosts = false
        isRefreshing = false
    }

    func loadMoreMyPosts() async {
        if isRefreshing || isLoadingPosts || isLoadingMorePosts { return }
        guard let current = myPosts, current.hasMore else { return }
        guard let nextCursor = current.nextCursor else { return }

        let nextCursorKey = cursorKey(for: nextCursor)
        if postsPagesByRequestCursor[nextCursorKey] != nil {
            appendRequestCursorIfNeeded(nextCursorKey)
            publishPostsFromCachedPages()
            return
        }

        isLoadingMorePosts = true
        errorMessage = nil

        do {
            let nextPage = try await fetchPostsPage(requestCursor: nextCursor)
            postsPagesByRequestCursor[nextCursorKey] = nextPage
            appendRequestCursorIfNeeded(nextCursorKey)
            publishPostsFromCachedPages()
            postsLastLoadedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingMorePosts = false
    }

    func loadMoreMyPostsIfNeeded(currentPost post: ProfilePost?) async {
        guard let post, let current = myPosts else { return }
        guard current.hasMore, !isLoadingMorePosts, !isLoadingPosts else { return }

        let posts = current.posts
        let threshold = posts.index(posts.endIndex, offsetBy: -4, limitedBy: posts.startIndex) ?? posts.startIndex

        guard let index = posts.firstIndex(where: { $0.id == post.id }),
              index >= threshold else {
            return
        }

        await loadMoreMyPosts()
    }

    func loadMyReposts(force: Bool = false) async {
        if isRefreshing || isLoadingReposts || isLoadingMoreReposts { return }
        let hasCachedData = myReposts != nil
        let isFresh: Bool = {
            guard !force,
                  hasCachedData,
                  let repostsLastLoadedAt else {
                return false
            }

            return Date().timeIntervalSince(repostsLastLoadedAt) < repostsTtl
        }()

        if isFresh {
            return
        }

        if hasCachedData {
            isRefreshing = true
        } else {
            isLoadingReposts = true
        }

        errorMessage = nil

        do {
            let firstPage = try await fetchRepostsPage(requestCursor: nil)
            repostPagesByRequestCursor = [cursorKey(for: nil): firstPage]
            repostRequestCursorOrder = [cursorKey(for: nil)]
            publishRepostsFromCachedPages()
            repostsLastLoadedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingReposts = false
        isRefreshing = false
    }

    func loadMoreMyReposts() async {
        if isRefreshing || isLoadingReposts || isLoadingMoreReposts { return }
        guard let current = myReposts, current.hasMore else { return }
        guard let nextCursor = current.nextCursor else { return }

        let nextCursorKey = cursorKey(for: nextCursor)
        if repostPagesByRequestCursor[nextCursorKey] != nil {
            appendRepostRequestCursorIfNeeded(nextCursorKey)
            publishRepostsFromCachedPages()
            return
        }

        isLoadingMoreReposts = true
        errorMessage = nil

        do {
            let nextPage = try await fetchRepostsPage(requestCursor: nextCursor)
            repostPagesByRequestCursor[nextCursorKey] = nextPage
            appendRepostRequestCursorIfNeeded(nextCursorKey)
            publishRepostsFromCachedPages()
            repostsLastLoadedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingMoreReposts = false
    }

    func loadMoreMyRepostsIfNeeded(currentRepost repost: ProfileRepost?) async {
        guard let repost, let current = myReposts else { return }
        guard current.hasMore, !isLoadingMoreReposts, !isLoadingReposts else { return }

        let reposts = current.reposts
        let threshold = reposts.index(reposts.endIndex, offsetBy: -4, limitedBy: reposts.startIndex) ?? reposts.startIndex

        guard let index = reposts.firstIndex(where: { $0.id == repost.id }),
              index >= threshold else {
            return
        }

        await loadMoreMyReposts()
    }

    func discography(for filter: ProfileDiscographyFilter, username: String? = nil) -> ProfileDiscographyCollection {
        if let username {
            return otherProfile(for: username)?.discographyByFilter[filter.apiValue] ?? .empty
        }
        return myDiscographyByFilter[filter.apiValue] ?? .empty
    }

    func loadMyDiscography(filter: ProfileDiscographyFilter, force: Bool = false) async {
        if isLoadingDiscography || isRefreshingDiscography { return }

        let filterKey = filter.apiValue
        let hasCachedData = myDiscographyByFilter[filterKey] != nil
        let isFresh: Bool = {
            guard !force,
                  hasCachedData,
                  let discographyLastLoadedAt else {
                return false
            }
            return Date().timeIntervalSince(discographyLastLoadedAt) < musicTtl
        }()
        if isFresh { return }

        if hasCachedData {
            isRefreshingDiscography = true
        } else {
            isLoadingDiscography = true
        }
        errorMessage = nil

        do {
            let firstPage = try await fetchDiscographyPage(filter: filter, username: nil, requestCursor: nil)
            myDiscographyPagesByFilter[filterKey] = [cursorKey(for: nil): firstPage]
            myDiscographyCursorOrderByFilter[filterKey] = [cursorKey(for: nil)]
            publishMyDiscographyFromCachedPages(filter: filter)
            discographyLastLoadedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingDiscography = false
        isRefreshingDiscography = false
    }

    func loadMoreMyDiscography(filter: ProfileDiscographyFilter) async {
        if isLoadingDiscography || isRefreshingDiscography || isLoadingMoreDiscography { return }

        let filterKey = filter.apiValue
        guard let current = myDiscographyByFilter[filterKey], current.hasMore else { return }
        guard let nextCursor = current.nextCursor else { return }

        let nextCursorKey = cursorKey(for: nextCursor)
        if myDiscographyPagesByFilter[filterKey]?[nextCursorKey] != nil {
            appendMyDiscographyRequestCursorIfNeeded(filter: filter, cursorKey: nextCursorKey)
            publishMyDiscographyFromCachedPages(filter: filter)
            return
        }

        isLoadingMoreDiscography = true
        errorMessage = nil

        do {
            let nextPage = try await fetchDiscographyPage(filter: filter, username: nil, requestCursor: nextCursor)
            var pages = myDiscographyPagesByFilter[filterKey] ?? [:]
            pages[nextCursorKey] = nextPage
            myDiscographyPagesByFilter[filterKey] = pages
            appendMyDiscographyRequestCursorIfNeeded(filter: filter, cursorKey: nextCursorKey)
            publishMyDiscographyFromCachedPages(filter: filter)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingMoreDiscography = false
    }

    func loadUserDiscography(username: String, filter: ProfileDiscographyFilter, force: Bool = false) async {
        let key = normalizeUsername(username)
        if otherDiscographyLoadingUsernames.contains(key) { return }

        let filterKey = filter.apiValue
        let cached = otherProfiles[key]?.discographyByFilter[filterKey]
        if !force,
           cached != nil,
           let discographyLoadedAt = otherProfiles[key]?.discographyLoadedAt,
           Date().timeIntervalSince(discographyLoadedAt) < musicTtl {
            return
        }

        otherDiscographyLoadingUsernames.insert(key)

        defer { otherDiscographyLoadingUsernames.remove(key) }

        do {
            let firstPage = try await fetchDiscographyPage(filter: filter, username: username, requestCursor: nil)
            var pagesByFilter = otherDiscographyPagesByUsername[key] ?? [:]
            pagesByFilter[filterKey] = [cursorKey(for: nil): firstPage]
            otherDiscographyPagesByUsername[key] = pagesByFilter

            var cursorOrderByFilter = otherDiscographyCursorOrderByUsername[key] ?? [:]
            cursorOrderByFilter[filterKey] = [cursorKey(for: nil)]
            otherDiscographyCursorOrderByUsername[key] = cursorOrderByFilter

            publishOtherDiscographyFromCachedPages(username: username, filter: filter)
        } catch {
            var data = otherProfiles[key] ?? OtherProfileData()
            data.errorMessage = error.localizedDescription
            otherProfiles[key] = data
        }
    }

    func loadMoreUserDiscography(username: String, filter: ProfileDiscographyFilter) async {
        let key = normalizeUsername(username)
        let filterKey = filter.apiValue
        guard let current = otherProfiles[key]?.discographyByFilter[filterKey], current.hasMore else { return }
        guard let nextCursor = current.nextCursor else { return }
        if otherDiscographyLoadingUsernames.contains(key) { return }

        let nextCursorKey = cursorKey(for: nextCursor)
        if otherDiscographyPagesByUsername[key]?[filterKey]?[nextCursorKey] != nil {
            appendOtherDiscographyRequestCursorIfNeeded(username: username, filter: filter, cursorKey: nextCursorKey)
            publishOtherDiscographyFromCachedPages(username: username, filter: filter)
            return
        }

        otherDiscographyLoadingUsernames.insert(key)

        defer { otherDiscographyLoadingUsernames.remove(key) }

        do {
            let nextPage = try await fetchDiscographyPage(filter: filter, username: username, requestCursor: nextCursor)
            var pagesByFilter = otherDiscographyPagesByUsername[key] ?? [:]
            var pages = pagesByFilter[filterKey] ?? [:]
            pages[nextCursorKey] = nextPage
            pagesByFilter[filterKey] = pages
            otherDiscographyPagesByUsername[key] = pagesByFilter
            appendOtherDiscographyRequestCursorIfNeeded(username: username, filter: filter, cursorKey: nextCursorKey)
            publishOtherDiscographyFromCachedPages(username: username, filter: filter)
        } catch {
            var data = otherProfiles[key] ?? OtherProfileData()
            data.errorMessage = error.localizedDescription
            otherProfiles[key] = data
        }
    }

    func loadUserMusic(username: String, force: Bool = false) async {
        let key = normalizeUsername(username)
        if otherMusicLoadingUsernames.contains(key) { return }

        let cached = otherProfiles[key]
        if !force,
           let musicLoadedAt = cached?.musicLoadedAt,
           Date().timeIntervalSince(musicLoadedAt) < musicTtl {
            return
        }

        otherMusicLoadingUsernames.insert(key)

        defer { otherMusicLoadingUsernames.remove(key) }

        do {
            async let likedFirst = fetchUserLikedSongsPage(username: username, requestCursor: nil)
            async let artistsFirst = fetchUserFollowingArtistsPage(username: username, requestCursor: nil)
            let (likedPage, artistsPage) = try await (likedFirst, artistsFirst)

            var data = otherProfiles[key] ?? OtherProfileData()
            data.likedSongs = likedPage.songs
            data.followingArtists = artistsPage.artists
            data.musicLoadedAt = Date()
            data.errorMessage = nil
            otherProfiles[key] = data
        } catch {
            var data = otherProfiles[key] ?? OtherProfileData()
            data.errorMessage = error.localizedDescription
            otherProfiles[key] = data
        }
    }

    func loadMyMusic(force: Bool = false) async {
        if isLoadingMusic || isRefreshingMusic { return }

        let hasCachedData = !likedSongs.isEmpty || !savedSongs.isEmpty || !followingArtistProfiles.isEmpty
        let isFresh: Bool = {
            guard !force,
                  hasCachedData,
                  let musicLastLoadedAt else {
                return false
            }
            return Date().timeIntervalSince(musicLastLoadedAt) < musicTtl
        }()
        if isFresh { return }

        if hasCachedData {
            isRefreshingMusic = true
        } else {
            isLoadingMusic = true
        }
        errorMessage = nil

        do {
            async let likedFirst = fetchLikedSongsPage(requestCursor: nil)
            async let savedFirst = fetchSavedSongsPage(requestCursor: nil)
            async let artistsFirst = fetchFollowingArtistsPage(requestCursor: nil)
            let (likedPage, savedPage, artistsPage) = try await (likedFirst, savedFirst, artistsFirst)

            likedSongsPagesByRequestCursor = [cursorKey(for: nil): likedPage]
            likedSongsRequestCursorOrder = [cursorKey(for: nil)]
            publishLikedSongsFromCachedPages()

            savedSongsPagesByRequestCursor = [cursorKey(for: nil): savedPage]
            savedSongsRequestCursorOrder = [cursorKey(for: nil)]
            publishSavedSongsFromCachedPages()

            followingArtistsPagesByRequestCursor = [cursorKey(for: nil): artistsPage]
            followingArtistsRequestCursorOrder = [cursorKey(for: nil)]
            publishFollowingArtistsFromCachedPages()

            musicLastLoadedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingMusic = false
        isRefreshingMusic = false
    }

    func loadMoreLikedTracks() async {
        if isLoadingMusic || isRefreshingMusic || isLoadingMoreLikedTracks { return }
        guard likedSongsHasMore, let nextCursor = likedSongsNextCursor else { return }

        let nextCursorKey = cursorKey(for: nextCursor)
        if likedSongsPagesByRequestCursor[nextCursorKey] != nil {
            appendLikedSongsRequestCursorIfNeeded(nextCursorKey)
            publishLikedSongsFromCachedPages()
            return
        }

        isLoadingMoreLikedTracks = true
        errorMessage = nil

        do {
            let nextPage = try await fetchLikedSongsPage(requestCursor: nextCursor)
            likedSongsPagesByRequestCursor[nextCursorKey] = nextPage
            appendLikedSongsRequestCursorIfNeeded(nextCursorKey)
            publishLikedSongsFromCachedPages()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingMoreLikedTracks = false
    }

    func loadMoreSavedAlbums() async {
        if isLoadingMusic || isRefreshingMusic || isLoadingMoreSavedAlbums { return }
        guard savedSongsHasMore, let nextCursor = savedSongsNextCursor else { return }

        let nextCursorKey = cursorKey(for: nextCursor)
        if savedSongsPagesByRequestCursor[nextCursorKey] != nil {
            appendSavedSongsRequestCursorIfNeeded(nextCursorKey)
            publishSavedSongsFromCachedPages()
            return
        }

        isLoadingMoreSavedAlbums = true
        errorMessage = nil

        do {
            let nextPage = try await fetchSavedSongsPage(requestCursor: nextCursor)
            savedSongsPagesByRequestCursor[nextCursorKey] = nextPage
            appendSavedSongsRequestCursorIfNeeded(nextCursorKey)
            publishSavedSongsFromCachedPages()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingMoreSavedAlbums = false
    }

    func loadMoreFollowingArtists() async {
        if isLoadingMusic || isRefreshingMusic || isLoadingMoreFollowingArtists { return }
        guard followingArtistsHasMore, let nextCursor = followingArtistsNextCursor else { return }

        let nextCursorKey = cursorKey(for: nextCursor)
        if followingArtistsPagesByRequestCursor[nextCursorKey] != nil {
            appendFollowingArtistsRequestCursorIfNeeded(nextCursorKey)
            publishFollowingArtistsFromCachedPages()
            return
        }

        isLoadingMoreFollowingArtists = true
        errorMessage = nil

        do {
            let nextPage = try await fetchFollowingArtistsPage(requestCursor: nextCursor)
            followingArtistsPagesByRequestCursor[nextCursorKey] = nextPage
            appendFollowingArtistsRequestCursorIfNeeded(nextCursorKey)
            publishFollowingArtistsFromCachedPages()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingMoreFollowingArtists = false
    }

    private func fetchPostsPage(requestCursor: String?) async throws -> ProfilePostsPage {
        var query: [String: String?] = [
            "limit": String(postsPageSize),
            "cursorCreatedAt": nil,
            "cursorId": nil,
        ]

        if let cursor = ProfilePostsCursor(rawValue: requestCursor) {
            query["cursorCreatedAt"] = cursor.cursorCreatedAt
            query["cursorId"] = cursor.cursorId
        }

        let response: (result: ProfilePostsResponse, metadata: APIMetadata?) =
            try await APIClient.shared.requestWithMetadata(
                Endpoints.myPosts,
                method: .get,
                query: query
            )

        let pagination = response.metadata?.pagination

        return ProfilePostsPage(
            requestCursor: requestCursor,
            posts: response.result.posts,
            nextCursor: pagination?.nextCursor,
            hasMore: pagination?.hasMore ?? false,
            limit: pagination?.limit ?? postsPageSize,
            fetchedAt: Date()
        )
    }

    private func fetchUserPostsPage(username: String, requestCursor: String?) async throws -> ProfilePostsPage {
        var query: [String: String?] = [
            "limit": String(postsPageSize),
            "cursorCreatedAt": nil,
            "cursorId": nil,
        ]

        if let cursor = ProfilePostsCursor(rawValue: requestCursor) {
            query["cursorCreatedAt"] = cursor.cursorCreatedAt
            query["cursorId"] = cursor.cursorId
        }

        let response: (result: ProfilePostsResponse, metadata: APIMetadata?) =
            try await APIClient.shared.requestWithMetadata(
                Endpoints.userPosts(username: username),
                method: .get,
                query: query
            )

        let pagination = response.metadata?.pagination

        return ProfilePostsPage(
            requestCursor: requestCursor,
            posts: response.result.posts,
            nextCursor: pagination?.nextCursor,
            hasMore: pagination?.hasMore ?? false,
            limit: pagination?.limit ?? postsPageSize,
            fetchedAt: Date()
        )
    }

    private func fetchRepostsPage(requestCursor: String?) async throws -> ProfileRepostsPage {
        var query: [String: String?] = [
            "limit": String(repostsPageSize),
            "cursorCreatedAt": nil,
            "cursorId": nil,
        ]

        if let cursor = ProfilePostsCursor(rawValue: requestCursor) {
            query["cursorCreatedAt"] = cursor.cursorCreatedAt
            query["cursorId"] = cursor.cursorId
        }

        let response: (result: ProfileRepostsResponse, metadata: APIMetadata?) =
            try await APIClient.shared.requestWithMetadata(
                Endpoints.myReposts,
                method: .get,
                query: query
            )

        let pagination = response.metadata?.pagination
        let mappedReposts = response.result.posts.map { row in
            ProfileRepost(
                id: row.id,
                post: row.post,
                originalUsername: row.post.owner.username
            )
        }

        return ProfileRepostsPage(
            requestCursor: requestCursor,
            reposts: mappedReposts,
            nextCursor: pagination?.nextCursor,
            hasMore: pagination?.hasMore ?? false,
            limit: pagination?.limit ?? repostsPageSize,
            fetchedAt: Date()
        )
    }

    private func fetchUserRepostsPage(username: String, requestCursor: String?) async throws -> ProfileRepostsPage {
        var query: [String: String?] = [
            "limit": String(repostsPageSize),
            "cursorCreatedAt": nil,
            "cursorId": nil,
        ]

        if let cursor = ProfilePostsCursor(rawValue: requestCursor) {
            query["cursorCreatedAt"] = cursor.cursorCreatedAt
            query["cursorId"] = cursor.cursorId
        }

        let response: (result: ProfileRepostsResponse, metadata: APIMetadata?) =
            try await APIClient.shared.requestWithMetadata(
                Endpoints.userReposts(username: username),
                method: .get,
                query: query
            )

        let pagination = response.metadata?.pagination
        let mappedReposts = response.result.posts.map { row in
            ProfileRepost(
                id: row.id,
                post: row.post,
                originalUsername: row.post.owner.username
            )
        }

        return ProfileRepostsPage(
            requestCursor: requestCursor,
            reposts: mappedReposts,
            nextCursor: pagination?.nextCursor,
            hasMore: pagination?.hasMore ?? false,
            limit: pagination?.limit ?? repostsPageSize,
            fetchedAt: Date()
        )
    }

    private func fetchUserLikedSongsPage(username: String, requestCursor: String?) async throws -> ProfileMusicSongPage {
        let response: (result: ProfileMusicSongResponse, metadata: APIMetadata?) =
            try await APIClient.shared.requestWithMetadata(
                Endpoints.musicUserLiked(username: username),
                method: .get,
                query: buildCursorQuery(limit: musicPageSize, requestCursor: requestCursor)
            )

        let pagination = response.metadata?.pagination
        return ProfileMusicSongPage(
            requestCursor: requestCursor,
            songs: response.result.songs,
            nextCursor: pagination?.nextCursor,
            hasMore: pagination?.hasMore ?? false,
            limit: pagination?.limit ?? musicPageSize,
            fetchedAt: Date()
        )
    }

    private func fetchUserFollowingArtistsPage(username: String, requestCursor: String?) async throws -> ProfileFollowingArtistPage {
        let response: (result: ProfileFollowingArtistResponse, metadata: APIMetadata?) =
            try await APIClient.shared.requestWithMetadata(
                Endpoints.musicUserFollowing(username: username),
                method: .get,
                query: buildCursorQuery(limit: musicPageSize, requestCursor: requestCursor)
            )

        let pagination = response.metadata?.pagination
        return ProfileFollowingArtistPage(
            requestCursor: requestCursor,
            artists: response.result.artists,
            nextCursor: pagination?.nextCursor,
            hasMore: pagination?.hasMore ?? false,
            limit: pagination?.limit ?? musicPageSize,
            fetchedAt: Date()
        )
    }

    private func fetchLikedSongsPage(requestCursor: String?) async throws -> ProfileMusicSongPage {
        let response: (result: ProfileMusicSongResponse, metadata: APIMetadata?) =
            try await APIClient.shared.requestWithMetadata(
                Endpoints.musicMeLiked,
                method: .get,
                query: buildCursorQuery(limit: musicPageSize, requestCursor: requestCursor)
            )

        let pagination = response.metadata?.pagination
        return ProfileMusicSongPage(
            requestCursor: requestCursor,
            songs: response.result.songs,
            nextCursor: pagination?.nextCursor,
            hasMore: pagination?.hasMore ?? false,
            limit: pagination?.limit ?? musicPageSize,
            fetchedAt: Date()
        )
    }

    private func fetchSavedSongsPage(requestCursor: String?) async throws -> ProfileMusicSongPage {
        let response: (result: ProfileMusicSongResponse, metadata: APIMetadata?) =
            try await APIClient.shared.requestWithMetadata(
                Endpoints.musicMeSaved,
                method: .get,
                query: buildCursorQuery(limit: musicPageSize, requestCursor: requestCursor)
            )

        let pagination = response.metadata?.pagination
        return ProfileMusicSongPage(
            requestCursor: requestCursor,
            songs: response.result.songs,
            nextCursor: pagination?.nextCursor,
            hasMore: pagination?.hasMore ?? false,
            limit: pagination?.limit ?? musicPageSize,
            fetchedAt: Date()
        )
    }

    private func fetchFollowingArtistsPage(requestCursor: String?) async throws -> ProfileFollowingArtistPage {
        let response: (result: ProfileFollowingArtistResponse, metadata: APIMetadata?) =
            try await APIClient.shared.requestWithMetadata(
                Endpoints.musicMeFollowing,
                method: .get,
                query: buildCursorQuery(limit: musicPageSize, requestCursor: requestCursor)
            )

        let pagination = response.metadata?.pagination
        return ProfileFollowingArtistPage(
            requestCursor: requestCursor,
            artists: response.result.artists,
            nextCursor: pagination?.nextCursor,
            hasMore: pagination?.hasMore ?? false,
            limit: pagination?.limit ?? musicPageSize,
            fetchedAt: Date()
        )
    }

    private func fetchDiscographyPage(
        filter: ProfileDiscographyFilter,
        username: String?,
        requestCursor: String?
    ) async throws -> ProfileDiscographyPage {
        let endpoint: APIEndpoint = {
            if let username {
                return Endpoints.userDiscography(username: username)
            }
            return Endpoints.myDiscography
        }()

        let response: (result: ProfileDiscographyResponse, metadata: APIMetadata?) =
            try await APIClient.shared.requestWithMetadata(
                endpoint,
                method: .get,
                query: buildDiscographyQuery(filter: filter, requestCursor: requestCursor)
            )

        let pagination = response.metadata?.pagination

        return ProfileDiscographyPage(
            requestCursor: requestCursor,
            filter: filter,
            latestRelease: response.result.latestRelease,
            items: response.result.items,
            nextCursor: pagination?.nextCursor,
            hasMore: pagination?.hasMore ?? false,
            limit: pagination?.limit ?? discographyPageSize,
            fetchedAt: Date()
        )
    }

    private func buildDiscographyQuery(
        filter: ProfileDiscographyFilter,
        requestCursor: String?
    ) -> [String: String?] {
        var query: [String: String?] = [
            "type": filter.apiValue,
            "limit": String(discographyPageSize),
            "cursorReleaseDate": nil,
            "cursorType": nil,
            "cursorId": nil,
        ]

        if let cursor = ProfileDiscographyCursor(rawValue: requestCursor) {
            query["cursorReleaseDate"] = cursor.cursorReleaseDate
            query["cursorType"] = cursor.cursorType
            query["cursorId"] = cursor.cursorId
        }

        return query
    }

    private func publishMyDiscographyFromCachedPages(filter: ProfileDiscographyFilter) {
        let filterKey = filter.apiValue
        let cursorOrder = myDiscographyCursorOrderByFilter[filterKey] ?? []
        let pages = myDiscographyPagesByFilter[filterKey] ?? [:]

        var mergedItems: [ProfileDiscographyItem] = []
        var seenItemIds = Set<String>()
        var latestRelease: ProfileDiscographyItem?
        var terminalNextCursor: String?
        var terminalHasMore = false
        var terminalLimit = discographyPageSize

        for requestCursorKey in cursorOrder {
            guard let page = pages[requestCursorKey] else { continue }

            if latestRelease == nil {
                latestRelease = page.latestRelease
            }

            for item in page.items where !seenItemIds.contains(item.id) {
                seenItemIds.insert(item.id)
                mergedItems.append(item)
            }

            terminalNextCursor = page.nextCursor
            terminalHasMore = page.hasMore
            terminalLimit = page.limit
        }

        let newState = ProfileDiscographyCollection(
            latestRelease: latestRelease,
            items: mergedItems,
            nextCursor: terminalNextCursor,
            hasMore: terminalHasMore,
            limit: terminalLimit
        )

        if myDiscographyByFilter[filterKey] != newState {
            myDiscographyByFilter[filterKey] = newState
        }
    }

    private func appendMyDiscographyRequestCursorIfNeeded(filter: ProfileDiscographyFilter, cursorKey: String) {
        let filterKey = filter.apiValue
        var order = myDiscographyCursorOrderByFilter[filterKey] ?? []
        guard !order.contains(cursorKey) else { return }
        order.append(cursorKey)
        myDiscographyCursorOrderByFilter[filterKey] = order
    }

    private func publishOtherDiscographyFromCachedPages(username: String, filter: ProfileDiscographyFilter) {
        let key = normalizeUsername(username)
        let filterKey = filter.apiValue
        let cursorOrder = otherDiscographyCursorOrderByUsername[key]?[filterKey] ?? []
        let pages = otherDiscographyPagesByUsername[key]?[filterKey] ?? [:]

        var mergedItems: [ProfileDiscographyItem] = []
        var seenItemIds = Set<String>()
        var latestRelease: ProfileDiscographyItem?
        var terminalNextCursor: String?
        var terminalHasMore = false
        var terminalLimit = discographyPageSize

        for requestCursorKey in cursorOrder {
            guard let page = pages[requestCursorKey] else { continue }

            if latestRelease == nil {
                latestRelease = page.latestRelease
            }

            for item in page.items where !seenItemIds.contains(item.id) {
                seenItemIds.insert(item.id)
                mergedItems.append(item)
            }

            terminalNextCursor = page.nextCursor
            terminalHasMore = page.hasMore
            terminalLimit = page.limit
        }

        let newState = ProfileDiscographyCollection(
            latestRelease: latestRelease,
            items: mergedItems,
            nextCursor: terminalNextCursor,
            hasMore: terminalHasMore,
            limit: terminalLimit
        )

        var data = otherProfiles[key] ?? OtherProfileData()
        if data.discographyByFilter[filterKey] != newState {
            data.discographyByFilter[filterKey] = newState
            data.discographyLoadedAt = Date()
            data.errorMessage = nil
            otherProfiles[key] = data
        }
    }

    private func appendOtherDiscographyRequestCursorIfNeeded(
        username: String,
        filter: ProfileDiscographyFilter,
        cursorKey: String
    ) {
        let key = normalizeUsername(username)
        let filterKey = filter.apiValue
        var orderByFilter = otherDiscographyCursorOrderByUsername[key] ?? [:]
        var order = orderByFilter[filterKey] ?? []
        guard !order.contains(cursorKey) else { return }
        order.append(cursorKey)
        orderByFilter[filterKey] = order
        otherDiscographyCursorOrderByUsername[key] = orderByFilter
    }

    private func publishPostsFromCachedPages() {
        var mergedPosts: [ProfilePost] = []
        var seenPostIds = Set<String>()
        var terminalNextCursor: String?
        var terminalHasMore = false
        var terminalLimit = postsPageSize

        for requestCursorKey in postsRequestCursorOrder {
            guard let page = postsPagesByRequestCursor[requestCursorKey] else { continue }

            for post in page.posts where !seenPostIds.contains(post.id) {
                seenPostIds.insert(post.id)
                mergedPosts.append(post)
            }

            terminalNextCursor = page.nextCursor
            terminalHasMore = page.hasMore
            terminalLimit = page.limit
        }

        let newState = ProfilePosts(
            posts: mergedPosts,
            nextCursor: terminalNextCursor,
            hasMore: terminalHasMore,
            limit: terminalLimit
        )

        if myPosts != newState {
            myPosts = newState
        }
    }

    private func appendRequestCursorIfNeeded(_ cursorKey: String) {
        guard !postsRequestCursorOrder.contains(cursorKey) else { return }
        postsRequestCursorOrder.append(cursorKey)
    }

    private func publishRepostsFromCachedPages() {
        var mergedReposts: [ProfileRepost] = []
        var seenRepostIds = Set<String>()
        var terminalNextCursor: String?
        var terminalHasMore = false
        var terminalLimit = repostsPageSize

        for requestCursorKey in repostRequestCursorOrder {
            guard let page = repostPagesByRequestCursor[requestCursorKey] else { continue }

            for repost in page.reposts where !seenRepostIds.contains(repost.id) {
                seenRepostIds.insert(repost.id)
                mergedReposts.append(repost)
            }

            terminalNextCursor = page.nextCursor
            terminalHasMore = page.hasMore
            terminalLimit = page.limit
        }

        let newState = ProfileReposts(
            reposts: mergedReposts,
            nextCursor: terminalNextCursor,
            hasMore: terminalHasMore,
            limit: terminalLimit
        )

        if myReposts != newState {
            myReposts = newState
        }
    }

    private func appendRepostRequestCursorIfNeeded(_ cursorKey: String) {
        guard !repostRequestCursorOrder.contains(cursorKey) else { return }
        repostRequestCursorOrder.append(cursorKey)
    }

    private func publishLikedSongsFromCachedPages() {
        var mergedSongs: [ProfileMusicSong] = []
        var seenSongIds = Set<String>()
        var terminalNextCursor: String?
        var terminalHasMore = false

        for requestCursorKey in likedSongsRequestCursorOrder {
            guard let page = likedSongsPagesByRequestCursor[requestCursorKey] else { continue }
            for song in page.songs where !seenSongIds.contains(song.id) {
                seenSongIds.insert(song.id)
                mergedSongs.append(song)
            }
            terminalNextCursor = page.nextCursor
            terminalHasMore = page.hasMore
        }

        likedTracks = mergedSongs.map {
            LibraryTrack(id: $0.id, name: $0.name, artworkUrl: $0.artworkUrl)
        }
        likedSongs = mergedSongs
        likedSongsNextCursor = terminalNextCursor
        likedSongsHasMore = terminalHasMore
    }

    private func publishSavedSongsFromCachedPages() {
        var mergedSongs: [ProfileMusicSong] = []
        var seenSongIds = Set<String>()
        var terminalNextCursor: String?
        var terminalHasMore = false

        for requestCursorKey in savedSongsRequestCursorOrder {
            guard let page = savedSongsPagesByRequestCursor[requestCursorKey] else { continue }
            for song in page.songs where !seenSongIds.contains(song.id) {
                seenSongIds.insert(song.id)
                mergedSongs.append(song)
            }
            terminalNextCursor = page.nextCursor
            terminalHasMore = page.hasMore
        }

        savedAlbums = mergedSongs.map {
            LibraryAlbum(id: $0.id, name: $0.name, artworkUrl: $0.artworkUrl)
        }
        savedSongs = mergedSongs
        savedSongsNextCursor = terminalNextCursor
        savedSongsHasMore = terminalHasMore
    }

    private func publishFollowingArtistsFromCachedPages() {
        var mergedArtists: [ProfileFollowingArtist] = []
        var seenArtistIds = Set<String>()
        var terminalNextCursor: String?
        var terminalHasMore = false

        for requestCursorKey in followingArtistsRequestCursorOrder {
            guard let page = followingArtistsPagesByRequestCursor[requestCursorKey] else { continue }
            for artist in page.artists where !seenArtistIds.contains(artist.id) {
                seenArtistIds.insert(artist.id)
                mergedArtists.append(artist)
            }
            terminalNextCursor = page.nextCursor
            terminalHasMore = page.hasMore
        }

        followingArtists = mergedArtists.map {
            LibraryArtist(id: $0.id, name: $0.name, imageUrl: $0.imageUrl)
        }
        followingArtistProfiles = mergedArtists
        followingArtistsNextCursor = terminalNextCursor
        followingArtistsHasMore = terminalHasMore
    }

    private func appendLikedSongsRequestCursorIfNeeded(_ cursorKey: String) {
        guard !likedSongsRequestCursorOrder.contains(cursorKey) else { return }
        likedSongsRequestCursorOrder.append(cursorKey)
    }

    private func appendSavedSongsRequestCursorIfNeeded(_ cursorKey: String) {
        guard !savedSongsRequestCursorOrder.contains(cursorKey) else { return }
        savedSongsRequestCursorOrder.append(cursorKey)
    }

    private func appendFollowingArtistsRequestCursorIfNeeded(_ cursorKey: String) {
        guard !followingArtistsRequestCursorOrder.contains(cursorKey) else { return }
        followingArtistsRequestCursorOrder.append(cursorKey)
    }

    private func buildCursorQuery(limit: Int, requestCursor: String?) -> [String: String?] {
        var query: [String: String?] = [
            "limit": String(limit),
            "cursorCreatedAt": nil,
            "cursorId": nil,
        ]

        if let cursor = ProfilePostsCursor(rawValue: requestCursor) {
            query["cursorCreatedAt"] = cursor.cursorCreatedAt
            query["cursorId"] = cursor.cursorId
        }

        return query
    }

    private func cursorKey(for cursor: String?) -> String {
        cursor ?? "__first__"
    }

    private func normalizeUsername(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func publishOtherPostsFromCachedPages(username: String) {
        let key = normalizeUsername(username)
        let cursorOrder = otherPostsCursorOrderByUsername[key] ?? []
        let pages = otherPostsPagesByUsername[key] ?? [:]

        var mergedPosts: [ProfilePost] = []
        var seenPostIds = Set<String>()
        var terminalNextCursor: String?
        var terminalHasMore = false
        var terminalLimit = postsPageSize

        for requestCursorKey in cursorOrder {
            guard let page = pages[requestCursorKey] else { continue }

            for post in page.posts where !seenPostIds.contains(post.id) {
                seenPostIds.insert(post.id)
                mergedPosts.append(post)
            }

            terminalNextCursor = page.nextCursor
            terminalHasMore = page.hasMore
            terminalLimit = page.limit
        }

        let newState = ProfilePosts(
            posts: mergedPosts,
            nextCursor: terminalNextCursor,
            hasMore: terminalHasMore,
            limit: terminalLimit
        )

        var data = otherProfiles[key] ?? OtherProfileData()
        if data.posts != newState {
            data.posts = newState
            data.postsLoadedAt = Date()
            otherProfiles[key] = data
        }
    }

    private func appendOtherPostsRequestCursorIfNeeded(username: String, cursorKey: String) {
        let key = normalizeUsername(username)
        var order = otherPostsCursorOrderByUsername[key] ?? []
        guard !order.contains(cursorKey) else { return }
        order.append(cursorKey)
        otherPostsCursorOrderByUsername[key] = order
    }

    private func publishOtherRepostsFromCachedPages(username: String) {
        let key = normalizeUsername(username)
        let cursorOrder = otherRepostsCursorOrderByUsername[key] ?? []
        let pages = otherRepostsPagesByUsername[key] ?? [:]

        var mergedReposts: [ProfileRepost] = []
        var seenRepostIds = Set<String>()
        var terminalNextCursor: String?
        var terminalHasMore = false
        var terminalLimit = repostsPageSize

        for requestCursorKey in cursorOrder {
            guard let page = pages[requestCursorKey] else { continue }

            for repost in page.reposts where !seenRepostIds.contains(repost.id) {
                seenRepostIds.insert(repost.id)
                mergedReposts.append(repost)
            }

            terminalNextCursor = page.nextCursor
            terminalHasMore = page.hasMore
            terminalLimit = page.limit
        }

        let newState = ProfileReposts(
            reposts: mergedReposts,
            nextCursor: terminalNextCursor,
            hasMore: terminalHasMore,
            limit: terminalLimit
        )

        var data = otherProfiles[key] ?? OtherProfileData()
        if data.reposts != newState {
            data.reposts = newState
            data.repostsLoadedAt = Date()
            otherProfiles[key] = data
        }
    }

    private func appendOtherRepostsRequestCursorIfNeeded(username: String, cursorKey: String) {
        let key = normalizeUsername(username)
        var order = otherRepostsCursorOrderByUsername[key] ?? []
        guard !order.contains(cursorKey) else { return }
        order.append(cursorKey)
        otherRepostsCursorOrderByUsername[key] = order
    }

    func updateProfile(
        draft: EditProfileDraft,
        baseline: EditProfileDraft,
        avatarJPEGData: Data?
    ) async throws {
        let requestAvatar = avatarJPEGData != nil
        let canChangeProfileType = me?.canUpdateProfileType ?? false
        let body = draft.updateBody(
            comparedTo: baseline,
            requestAvatar: requestAvatar,
            canChangeProfileType: canChangeProfileType
        )

        guard !body.isEmpty else { return }

        let response: ProfileUpdateResponse = try await APIClient.shared.request(
            Endpoints.updateProfile,
            method: .post,
            body: body,
            preserveBodyKeyNames: true
        )

        if let avatarJPEGData, let upload = response.avatarUpload {
            try await uploadAvatar(jpegData: avatarJPEGData, upload: upload)
        }

        await loadMe(force: true)
    }

    private func uploadAvatar(jpegData: Data, upload: AvatarUploadInfo) async throws {
        guard jpegData.count <= upload.maxBytes else {
            throw ProfileUpdateError.avatarTooLarge
        }

        guard let uploadURL = URL(string: upload.uploadUrl) else {
            throw ProfileUpdateError.invalidUploadURL
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue(upload.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = jpegData

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw ProfileUpdateError.uploadFailed
        }

        try await APIClient.shared.requestVoid(
            Endpoints.meAvatar,
            method: .patch,
            body: ConfirmAvatarBody(objectKey: upload.objectKey, avatarUrl: upload.avatarUrl),
            preserveBodyKeyNames: true
        )
    }
    
    func reset() {
        // clears all profile data
        me = nil
        myPosts = nil
        myReposts = nil
        likedTracks = []
        likedSongs = []
        savedAlbums = []
        savedSongs = []
        followingArtists = []
        followingArtistProfiles = []
        myDiscographyByFilter = [:]
        myDiscographyPagesByFilter = [:]
        myDiscographyCursorOrderByFilter = [:]
        otherDiscographyPagesByUsername = [:]
        otherDiscographyCursorOrderByUsername = [:]
        otherProfiles = [:]
        otherProfileLoadingUsernames = []
        otherPostsLoadingUsernames = []
        otherRepostsLoadingUsernames = []
        followActionUsernames = []
        otherPostsPagesByUsername = [:]
        otherPostsCursorOrderByUsername = [:]
        otherRepostsPagesByUsername = [:]
        otherRepostsCursorOrderByUsername = [:]
    }
}

#if DEBUG
extension ProfileStore {
    static var preview: ProfileStore {
        let store = ProfileStore()
        store.me = FullUser.preview
        store.myPosts = .empty
        store.myReposts = .empty
        store.likedSongs = [
            ProfileMusicSong(
                id: "1",
                name: "Test Track",
                source: "apple_music",
                albumId: nil,
                artistId: "a1",
                sourceId: "123",
                artworkUrl: nil,
                artistName: "Preview Artist",
                viewer: nil
            ),
            ProfileMusicSong(
                id: "2",
                name: "Niche Track",
                source: "internal",
                albumId: nil,
                artistId: "a2",
                sourceId: "456",
                artworkUrl: nil,
                artistName: "Niche Artist",
                viewer: nil
            ),
        ]
        store.savedAlbums = [
            LibraryAlbum(id: "1", name: "Saved Album", artworkUrl: nil)
        ]
        store.followingArtists = [
            LibraryArtist(id: "1", name: "Preview Artist", imageUrl: nil)
        ]
        return store
    }
}

extension FullUser {
    static let preview = FullUser(
        id: "C9Qgjii52AND2kArKc0G6Q",
        username: "ryanr",
        displayName: "Ryan",
        avatarUrl: "https://cdn.nichemusic.app/avatars/C9Qgjii52AND2kArKc0G6Q/avatar-RFrc-_FO84XJs7-Y.jpg",
        bio: "yoo",
        profileType: "user",
        typeUpdatedAt: "2026-03-14T12:34:27.652062+00:00",
        createdAt: "2026-03-14 12:34:27.652062+00",
        updatedAt: "2026-04-24 18:49:21.688104+00",
        locationName: "Poolesville, Maryland",
        isPrivate: false,
        isVerified: false,
        followersCount: 10,
        followingCount: 12,
        friendCount: 9,
        postsCount: 22,
        profileSongId: "gtwXgmWgP7xdRtEX69uKoA",
        profileSong: ProfileSong(
            id: "gtwXgmWgP7xdRtEX69uKoA",
            name: "I miss when we talked",
            artist: ProfileTrackArtist(name: "Memories Of You"),
            source: "apple_music",
            sourceId: "1886302976",
            artworkUrl: "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/90/46/93/90469335-df2a-e653-cc7d-e85b7be6ab25/4070335832955.jpg/{w}x{h}bb.jpg",
            previewUrl: nil
        ),
        spotifyAccount: "9z2iqrcgso77nta5r23akefww",
        tiktokHandle: "ryanramenn",
        instagramHandle: "ryanramenn",
        allowMessagesFrom: "all",
        allowGroupInvites: true,
        badges: [
            ProfileBadgeSlot(
                badge: ProfileBadge(
                    id: "preview-ceo",
                    text: "CEO",
                    colorHex: "ffbb00",
                    createdAt: nil
                ),
                index: 0
            ),
            ProfileBadgeSlot(
                badge: ProfileBadge(
                    id: "preview-admin",
                    text: "Admin",
                    colorHex: "962a72",
                    createdAt: nil
                ),
                index: 1
            ),
        ]
    )
}
#endif
