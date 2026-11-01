//
//  PlaylistOptionsMenu.swift
//  Niche Music
//

import SwiftUI

struct PlaylistOptionsMenu: View {
    let playlist: PlaylistDetail
    let isOwner: Bool
    let onEdit: () -> Void
    let onAddTracks: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Menu {
            if isOwner {
                Button(action: onEdit) {
                    Label("Edit Playlist", systemImage: "pencil")
                }

                Button(action: onAddTracks) {
                    Label("Add Tracks", systemImage: "plus")
                }
            }

            ShareLink(item: MusicShareLinks.playlist(playlist.id), subject: Text(playlist.name)) {
                Label("Share Playlist", systemImage: "square.and.arrow.up")
            }

            if isOwner {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Playlist", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
    }
}
