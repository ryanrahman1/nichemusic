//
//  ProfileUpdateError.swift
//  Niche Music
//

import Foundation

enum ProfileUpdateError: LocalizedError {
    case avatarTooLarge
    case invalidUploadURL
    case uploadFailed
    case profileTypeCooldown

    var errorDescription: String? {
        switch self {
        case .avatarTooLarge:
            "That photo is too large. Choose a smaller image."
        case .invalidUploadURL:
            "Couldn't start avatar upload."
        case .uploadFailed:
            "Couldn't upload your new photo."
        case .profileTypeCooldown:
            "You can change your profile type again 14 days after your last change."
        }
    }
}
