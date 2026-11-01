//
//  PostMediaPrefetch.swift
//  Niche Music
//

import Foundation
import Kingfisher

extension Post {
    func prefetchDetailMedia() {
        let feedPost = asFeedItem.post
        FeedPlayerCache.shared.prefetch(media: feedPost.activePostMedia)

        if let imageURL = feedPost.primaryDisplayImageURL {
            KingfisherManager.shared.retrieveImage(with: imageURL) { _ in }
        }

        if let avatarUrl = feedPost.owner.avatarUrl,
           let avatarURL = URL(string: avatarUrl) {
            KingfisherManager.shared.retrieveImage(with: avatarURL) { _ in }
        }
    }
}
