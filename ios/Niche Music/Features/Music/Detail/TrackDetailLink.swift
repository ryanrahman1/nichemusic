//
//  TrackDetailLink.swift
//  Niche Music
//

import SwiftUI

struct TrackDetailReference: Equatable, Hashable {
    let id: String?
    let source: String?
    let sourceId: String?

    var canOpen: Bool {
        if source == "apple_music", let sourceId, !sourceId.isEmpty { return true }
        if let id, !id.isEmpty { return true }
        if let sourceId, !sourceId.isEmpty { return true }
        return false
    }
}

extension TrackDetailReference {
    init(_ track: FeedTrack) {
        id = track.id
        source = track.source
        sourceId = track.sourceId
    }

    init(_ track: FeedContentTrack) {
        id = track.id
        source = track.source
        sourceId = track.sourceId
    }

    init(_ track: PostTrack) {
        id = track.id
        source = track.source
        sourceId = track.sourceId
    }

    init(_ track: TrackCommentSharedTrack) {
        id = track.id
        source = track.source
        sourceId = track.sourceId
    }

    init(_ song: ProfileSong) {
        id = song.id
        source = song.source
        sourceId = song.sourceId
    }

    init(_ song: ProfileMusicSong) {
        id = song.id
        source = song.source
        sourceId = song.sourceId
    }

    init(_ track: PostNicheTrack) {
        id = track.id
        source = "niche"
        sourceId = nil
    }
}

extension FeedItem {
    var trackDetailReference: TrackDetailReference? {
        if let track = post.track {
            return TrackDetailReference(track)
        }
        if let track = post.content.track {
            return TrackDetailReference(track)
        }
        if let nicheTrack = post.resolvedNicheTrack {
            return TrackDetailReference(nicheTrack)
        }
        return nil
    }

    var postCommentsSubtitle: String {
        if let trackName = post.displayTrackTitle {
            return trackName
        }
        if let caption = post.content.caption?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !caption.isEmpty {
            return caption
        }
        return "@\(post.owner.username)"
    }
}

struct TrackDetailLink<Label: View>: View {
    let reference: TrackDetailReference
    @ViewBuilder var label: () -> Label

    @Environment(\.sheetExternalNavigation) private var sheetExternalNavigation

    var body: some View {
        if reference.canOpen {
            if let sheetExternalNavigation {
                Button {
                    sheetExternalNavigation.dismissAndOpenTrackDetail(reference)
                } label: {
                    label()
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    trackDetailDestination(reference)
                } label: {
                    label()
                }
                .buttonStyle(.plain)
            }
        } else {
            label()
        }
    }
}

@ViewBuilder
func trackDetailDestination(_ reference: TrackDetailReference) -> some View {
    if reference.source == "apple_music",
       let sourceId = reference.sourceId,
       !sourceId.isEmpty {
        AppleMusicDetailView(sourceId: sourceId)
            .toolbarVisibility(.hidden, for: .tabBar)
    } else if let id = reference.id, !id.isEmpty {
        NicheTrackDetailView(trackId: id)
            .toolbarVisibility(.hidden, for: .tabBar)
    } else if let sourceId = reference.sourceId, !sourceId.isEmpty {
        AppleMusicDetailView(sourceId: sourceId)
            .toolbarVisibility(.hidden, for: .tabBar)
    }
}
