//
//  PublishPostCompletionCover.swift
//  Niche Music
//

import SwiftUI

struct PublishPostCompletionCover: View {
    let destination: PublishMusicDestination

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var musicStore: MusicStore
    @EnvironmentObject private var musicPlayer: MusicPlayer
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var appNavigation: AppNavigationRouter
    @EnvironmentObject private var playlistStore: PlaylistStore

    var body: some View {
        NavigationStack {
            Group {
                switch destination {
                case .track(let trackId):
                    NicheTrackDetailView(trackId: trackId)
                case .release(let releaseId):
                    NicheAlbumDetailView(albumId: releaseId)
                }
            }
            .environmentObject(musicStore)
            .environmentObject(musicPlayer)
            .environmentObject(session)
            .environmentObject(appNavigation)
            .environmentObject(playlistStore)
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
