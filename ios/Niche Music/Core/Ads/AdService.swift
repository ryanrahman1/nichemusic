//
//  AdService.swift
//  Niche Music
//
//  Created by Ryan Rahman on 6/1/26.
//


import Foundation
import GoogleMobileAds

final class AdService {
    static let shared = AdService()

    private init() {}

    enum Unit {
        static let feedVideoAds = "ca-app-pub-3940256099942544/3986624511"
        // ca-app-pub-2574187180523893/9748271777
        // replace with your real "feed_video_ads" unit before release
    }
}
