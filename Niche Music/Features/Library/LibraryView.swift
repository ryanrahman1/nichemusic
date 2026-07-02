//
//  LibraryView.swift
//  Niche Music
//

import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var playlistStore: PlaylistStore

    @State private var selectedTab: LibraryTab = .yourLibrary
    @State private var browseRoute: LibraryBrowseRoute?
    @State private var searchRoute: LibrarySearchRoute?

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    libraryHeader
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 12)

                    tabContent
                }
                .padding(.bottom, 120)
            }
            .background(Theme.backgroundColor.ignoresSafeArea())
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $browseRoute) { route in
                LibraryBrowseView(route: route)
            }
            .navigationDestination(item: $searchRoute) { route in
                LibrarySearchView(source: route.source)
            }
        }
        .task {
            async let trending: Void = libraryStore.loadTrendingPreview()
            async let music: Void = profileStore.loadMyMusic()
            async let playlists: Void = playlistStore.loadMyPlaylists()
            _ = await (trending, music, playlists)
        }
        .refreshable {
            async let trending: Void = libraryStore.loadTrendingPreview(force: true)
            async let music: Void = profileStore.loadMyMusic(force: true)
            async let playlists: Void = playlistStore.loadMyPlaylists(force: true)
            _ = await (trending, music, playlists)
        }
    }

    private var libraryHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Library")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            libraryTabMenu
        }
    }

    private var libraryTabMenu: some View {
        Menu {
            Picker("Library", selection: $selectedTab) {
                ForEach(LibraryTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedTab.rawValue)
                    .font(.system(size: 15, weight: .semibold))

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.92))
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .yourLibrary:
            LibraryYourTabView()
        case .appleMusic:
            LibraryCatalogTabView(
                source: .appleMusic,
                browseRoute: $browseRoute,
                searchRoute: $searchRoute
            )
        }
    }
}

#Preview {
    LibraryView()
        .environmentObject(LibraryStore())
        .environmentObject(ProfileStore())
        .environmentObject(PlaylistStore())
}
