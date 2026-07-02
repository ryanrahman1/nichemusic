//
//  PlaybackPreferencesStore.swift
//  Niche Music
//

import Foundation

struct PlaybackPreferences: Equatable, Codable {
    var shuffle: Bool
    var repeatMode: PlayerRepeatMode

    static let `default` = PlaybackPreferences(shuffle: false, repeatMode: .off)
}

enum PlaybackSessionContext: Equatable, Hashable {
    case general
    case playlist(id: String)

    var storageKey: String {
        switch self {
        case .general:
            return "playback.preferences.general"
        case .playlist(let id):
            return "playback.preferences.playlist.\(id)"
        }
    }
}

@MainActor
final class PlaybackPreferencesStore {
    static let shared = PlaybackPreferencesStore()

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(for context: PlaybackSessionContext) -> PlaybackPreferences {
        guard
            let data = defaults.data(forKey: context.storageKey),
            let prefs = try? decoder.decode(PlaybackPreferences.self, from: data)
        else {
            return .default
        }
        return prefs
    }

    func save(_ preferences: PlaybackPreferences, for context: PlaybackSessionContext) {
        guard let data = try? encoder.encode(preferences) else { return }
        defaults.set(data, forKey: context.storageKey)
    }
}
