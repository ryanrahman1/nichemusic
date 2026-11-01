//
//  DiscoverStore.swift
//  Niche Music
//

import Foundation
import Kingfisher
import Combine

@MainActor
final class DiscoverStore: ObservableObject {
    @Published private(set) var home: DiscoverHomeResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?

    private let api = APIClient.shared
    private let sectionLimit = 10
    private let cacheTTL: TimeInterval = 120
    private var loadedAt: Date?

    func loadHome(force: Bool = false) async {
        if isLoading { return }
        if !force,
           let loadedAt,
           Date().timeIntervalSince(loadedAt) < cacheTTL,
           home != nil {
            return
        }

        let isInitialLoad = home == nil
        if isInitialLoad {
            isLoading = true
        } else {
            isRefreshing = true
        }
        errorMessage = nil

        do {
            let response: DiscoverHomeResponse = try await api.request(
                Endpoints.discoverHome,
                method: .get,
                query: [
                    "sectionLimit": String(sectionLimit),
                ]
            )
            home = response
            loadedAt = Date()
            prefetchArtwork(from: response)
        } catch {
            if home == nil {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
        isRefreshing = false
    }

    func refresh() async {
        await loadHome(force: true)
    }

    private func prefetchArtwork(from response: DiscoverHomeResponse) {
        var urls: [URL] = []

        func appendArtwork(_ template: String?) {
            if let url = resolvedAppleArtworkURL(template, size: 260) {
                urls.append(url)
            }
        }

        let sections = response.sections
        for track in sections.forYou + sections.trendingNicheTracks + sections.newNicheReleases {
            appendArtwork(track.artworkUrl)
        }
        for playlist in sections.featuredPlaylists {
            if let imageUrl = playlist.imageUrl, let url = URL(string: imageUrl) {
                urls.append(url)
            }
        }
        if let spotlight = sections.artistSpotlight {
            appendArtwork(spotlight.imageUrl)
        }
        for profile in sections.popularProfiles {
            if let avatarUrl = profile.avatarUrl, let url = URL(string: avatarUrl) {
                urls.append(url)
            }
        }
        for post in sections.recentPosts {
            if let url = post.asPost.thumbnailURL {
                urls.append(url)
            }
        }

        for url in urls.prefix(40) {
            KingfisherManager.shared.retrieveImage(with: url) { _ in }
        }
    }
}
