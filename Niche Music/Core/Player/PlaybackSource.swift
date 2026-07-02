//
//  PlaybackSource.swift
//  Niche Music
//

import Foundation

enum PlaybackSource {
    case playlist(String)
    case album(String)
    case custom(String)

    var label: String {
        switch self {
        case .playlist(let name), .album(let name), .custom(let name):
            return name
        }
    }
}
