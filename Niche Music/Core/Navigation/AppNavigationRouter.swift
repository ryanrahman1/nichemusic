//
//  AppNavigationRouter.swift
//  Niche Music
//

import SwiftUI
import Combine

struct ProfileNavigationRoute: Identifiable, Hashable {
    let username: String
    var id: String { username }
}

struct TrackDetailNavigationRoute: Identifiable, Hashable {
    let reference: TrackDetailReference

    var id: String {
        if let trackId = reference.id, !trackId.isEmpty {
            return "niche:\(trackId)"
        }
        if let sourceId = reference.sourceId, !sourceId.isEmpty {
            return "apple:\(reference.source ?? "apple_music"):\(sourceId)"
        }
        return "track-detail-unknown"
    }
}

struct PostDetailNavigationRoute: Identifiable, Hashable {
    let postId: String

    var id: String { postId }
}

struct PlaylistDetailNavigationRoute: Identifiable, Hashable {
    let playlistId: String

    var id: String { playlistId }
}

struct AppleArtistNavigationRoute: Identifiable, Hashable {
    let sourceId: String

    var id: String { sourceId }
}

struct AppleAlbumNavigationRoute: Identifiable, Hashable {
    let sourceId: String

    var id: String { sourceId }
}

struct NicheAlbumNavigationRoute: Identifiable, Hashable {
    let albumId: String

    var id: String { albumId }
}

struct SheetExternalNavigation {
    let dismissAndOpenProfile: (String) -> Void
    let dismissAndOpenTrackDetail: (TrackDetailReference) -> Void
}

private struct SheetExternalNavigationKey: EnvironmentKey {
    static let defaultValue: SheetExternalNavigation? = nil
}

/// Optional extra dismiss (e.g. full-screen cover) when navigating out of a nested sheet.
private struct SheetPresentationContainerDismissKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var sheetExternalNavigation: SheetExternalNavigation? {
        get { self[SheetExternalNavigationKey.self] }
        set { self[SheetExternalNavigationKey.self] = newValue }
    }

    var sheetPresentationContainerDismiss: (() -> Void)? {
        get { self[SheetPresentationContainerDismissKey.self] }
        set { self[SheetPresentationContainerDismissKey.self] = newValue }
    }
}

extension View {
    func sheetPresentationContainerDismiss(_ action: @escaping () -> Void) -> some View {
        environment(\.sheetPresentationContainerDismiss, action)
    }
}

@MainActor
final class AppNavigationRouter: ObservableObject {
    @Published var profileRoute: ProfileNavigationRoute?
    @Published var trackDetailRoute: TrackDetailNavigationRoute?
    @Published var modalProfileRoute: ProfileNavigationRoute?
    @Published var modalTrackDetailRoute: TrackDetailNavigationRoute?
    @Published var modalPostRoute: PostDetailNavigationRoute?
    @Published var modalPlaylistRoute: PlaylistDetailNavigationRoute?
    @Published var modalAppleArtistRoute: AppleArtistNavigationRoute?
    @Published var modalAppleAlbumRoute: AppleAlbumNavigationRoute?
    @Published var modalNicheAlbumRoute: NicheAlbumNavigationRoute?
    @Published var selectedTab: Int?

    private let sheetDismissDelayNanoseconds: UInt64 = 350_000_000

    func sheetExternalNavigation(
        dismiss: @escaping () -> Void,
        alsoDismissContainer: (() -> Void)? = nil
    ) -> SheetExternalNavigation {
        let dismissAll = {
            dismiss()
            alsoDismissContainer?()
        }
        return SheetExternalNavigation(
            dismissAndOpenProfile: { [weak self] username in
                self?.openProfileAfterDismissingSheet(username, dismiss: dismissAll)
            },
            dismissAndOpenTrackDetail: { [weak self] reference in
                self?.openTrackDetailAfterDismissingSheet(reference, dismiss: dismissAll)
            }
        )
    }

    func openProfileAfterDismissingSheet(_ username: String, dismiss: @escaping () -> Void) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: sheetDismissDelayNanoseconds)
            profileRoute = ProfileNavigationRoute(username: username)
        }
    }

    func openTrackDetailAfterDismissingSheet(
        _ reference: TrackDetailReference,
        dismiss: @escaping () -> Void
    ) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: sheetDismissDelayNanoseconds)
            trackDetailRoute = TrackDetailNavigationRoute(reference: reference)
        }
    }
}

struct ExternalNavigationDestinationsModifier: ViewModifier {
    @EnvironmentObject private var appNavigation: AppNavigationRouter

    func body(content: Content) -> some View {
        content
            .navigationDestination(item: $appNavigation.profileRoute) { route in
                OtherProfileView(username: route.username)
                    .toolbarVisibility(.hidden, for: .tabBar)
            }
            .navigationDestination(item: $appNavigation.trackDetailRoute) { route in
                trackDetailDestination(route.reference)
            }
    }
}

extension View {
    func externalNavigationDestinations() -> some View {
        modifier(ExternalNavigationDestinationsModifier())
    }
}
