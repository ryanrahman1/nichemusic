//
//  ProfileArtistDiscographyTabView.swift
//  Niche Music
//

import SwiftUI

struct ProfileArtistDiscographyTabView: View {
    enum Scope: Equatable {
        case ownProfile
        case user(username: String)
    }

    let scope: Scope

    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var musicStore: MusicStore
    @EnvironmentObject private var musicPlayer: MusicPlayer
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var appNavigation: AppNavigationRouter
    @EnvironmentObject private var playlistStore: PlaylistStore

    @State private var selectedFilter: ProfileDiscographyFilter = .all
    @State private var showPublishFlow = false
    @State private var pendingPublishDestination: PublishMusicDestination?
    @State private var publishedDestination: PublishMusicDestination?

    private var canManageMusic: Bool {
        if case .ownProfile = scope { return true }
        return false
    }

    private var username: String? {
        if case .user(let username) = scope { return username }
        return nil
    }

    private var collection: ProfileDiscographyCollection {
        profileStore.discography(for: selectedFilter, username: username)
    }

    private var isLoading: Bool {
        switch scope {
        case .ownProfile:
            return profileStore.isLoadingDiscography
                && collection.items.isEmpty
                && collection.latestRelease == nil
        case .user(let username):
            return profileStore.otherDiscographyLoadingUsernames.contains(normalizedUsername(username))
                && collection.items.isEmpty
                && collection.latestRelease == nil
        }
    }

    private var isLoadingMore: Bool {
        switch scope {
        case .ownProfile:
            return profileStore.isLoadingMoreDiscography
        case .user(let username):
            return profileStore.otherDiscographyLoadingUsernames.contains(normalizedUsername(username))
                && !collection.items.isEmpty
        }
    }

    private var excludedLatestReleaseID: String? {
        guard selectedFilter == .all else { return nil }
        return collection.latestRelease?.id
    }

    private var albumItems: [ProfileDiscographyItem] {
        collection.items.filter { $0.type == "album" || $0.type == "ep" }
    }

    private var singleItems: [ProfileDiscographyItem] {
        filteredItems(type: "single")
    }

    private var featuredItems: [ProfileDiscographyItem] {
        filteredItems(type: "featured_on")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if canManageMusic {
                Button {
                    showPublishFlow = true
                    PublishHaptics.tap()
                } label: {
                    Label("Upload music", systemImage: "arrow.up.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            ProfileDiscographyFilterChips(selectedFilter: $selectedFilter)

            if isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            } else if collection.items.isEmpty && collection.latestRelease == nil {
                Text(emptyMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
            } else {
                if selectedFilter == .all, let latestRelease = collection.latestRelease {
                    ProfileDiscographyLatestReleaseCard(item: latestRelease, canManage: canManageMusic)
                }

                if selectedFilter == .all {
                    discographySection(title: "Albums & EPs", items: albumItems)
                    discographySection(title: "Singles", items: singleItems)
                    discographySection(title: "Featured On", items: featuredItems)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(collection.items) { item in
                            ProfileDiscographyRow(item: item, canManage: canManageMusic)
                                .onAppear {
                                    if item.id == collection.items.last?.id {
                                        Task { await loadMoreIfNeeded() }
                                    }
                                }
                        }

                        if isLoadingMore {
                            ProgressView()
                                .tint(.white)
                                .padding(.vertical, 16)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: taskKey) {
            await loadContent(force: false)
        }
        .onChange(of: selectedFilter) { _, _ in
            Task { await loadContent(force: false) }
        }
        .fullScreenCover(isPresented: $showPublishFlow, onDismiss: {
            if let destination = pendingPublishDestination {
                publishedDestination = destination
                pendingPublishDestination = nil
            }
        }) {
            PublishMusicFlowView { destination in
                pendingPublishDestination = destination
                showPublishFlow = false
            }
            .environmentObject(profileStore)
        }
        .fullScreenCover(item: $publishedDestination) { destination in
            PublishPostCompletionCover(destination: destination)
                .environmentObject(musicStore)
                .environmentObject(musicPlayer)
                .environmentObject(session)
                .environmentObject(appNavigation)
                .environmentObject(playlistStore)
        }
    }

    private var taskKey: String {
        switch scope {
        case .ownProfile:
            return "own-\(selectedFilter.apiValue)"
        case .user(let username):
            return "\(normalizedUsername(username))-\(selectedFilter.apiValue)"
        }
    }

    private var emptyMessage: String {
        switch selectedFilter {
        case .all:
            return "Released music will show up here."
        case .album:
            return "No albums yet."
        case .single:
            return "No singles yet."
        case .featuredOn:
            return "Featured appearances will show up here."
        }
    }

    @ViewBuilder
    private func discographySection(title: String, items: [ProfileDiscographyItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 8)

                ForEach(items) { item in
                    ProfileDiscographyRow(item: item, canManage: canManageMusic)
                        .onAppear {
                            if item.id == items.last?.id {
                                Task { await loadMoreIfNeeded() }
                            }
                        }
                }
            }
        }
    }

    private func filteredItems(type: String) -> [ProfileDiscographyItem] {
        collection.items.filter { item in
            item.type == type && item.id != excludedLatestReleaseID
        }
    }

    private func loadContent(force: Bool) async {
        switch scope {
        case .ownProfile:
            await profileStore.loadMyDiscography(filter: selectedFilter, force: force)
        case .user(let username):
            await profileStore.loadUserDiscography(username: username, filter: selectedFilter, force: force)
        }
    }

    private func loadMoreIfNeeded() async {
        guard collection.hasMore else { return }

        switch scope {
        case .ownProfile:
            await profileStore.loadMoreMyDiscography(filter: selectedFilter)
        case .user(let username):
            await profileStore.loadMoreUserDiscography(username: username, filter: selectedFilter)
        }
    }

    private func normalizedUsername(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
