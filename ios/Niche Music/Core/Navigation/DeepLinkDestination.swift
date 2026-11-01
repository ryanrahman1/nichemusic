//
//  DeepLinkDestination.swift
//  Niche Music
//

import Foundation

enum DeepLinkDestination: Equatable {
    case post(id: String, commentId: String? = nil)
    case profile(username: String)
    case track(TrackDetailReference)
    case shareTrack(id: String)
    case shareArtist(id: String)
    case appleArtist(sourceId: String)
    case appleAlbum(sourceId: String)
    case nicheAlbum(id: String)
    case playlist(id: String)
    case conversation(id: String)
    case externalURL(URL)
}

enum DeepLinkSource: Equatable {
    case universalLink
    case customScheme
    case pushNotification
    case inAppNotification
}
