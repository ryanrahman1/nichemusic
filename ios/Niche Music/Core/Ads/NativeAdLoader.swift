//
//  NativeAdLoader.swift
//  Niche Music
//
//  Created by Ryan Rahman on 6/1/26.
//


import Foundation
import GoogleMobileAds
import UIKit
import Combine

@MainActor
final class NativeAdLoader: NSObject, ObservableObject {
    @Published private(set) var ads: [NativeAd] = []
    @Published private(set) var isLoading = false

    private var adLoader: AdLoader?

    private let maxPoolSize = 20
    private let lowInventoryThreshold = 5
    private let batchSize = 8

    func loadFeedAds(count: Int = 8) {
        guard !isLoading else { return }
        guard ads.count < maxPoolSize else { return }

        isLoading = true

        let safeCount = min(count, maxPoolSize - ads.count)

        let multipleAdsOptions = MultipleAdsAdLoaderOptions()
        multipleAdsOptions.numberOfAds = safeCount

        let videoOptions = VideoOptions()
        videoOptions.shouldStartMuted = true

        adLoader = AdLoader(
            adUnitID: AdService.Unit.feedVideoAds,
            rootViewController: UIApplication.shared.currentRootViewController,
            adTypes: [.native],
            options: [multipleAdsOptions, videoOptions]
        )

        adLoader?.delegate = self
        adLoader?.load(Request())
    }

    func ensureInventory() {
        guard ads.count < lowInventoryThreshold else { return }
        loadFeedAds(count: batchSize)
    }

    func maintainInventory(requiredAds: Int) {
        guard !isLoading else { return }

        let target = min(max(requiredAds, lowInventoryThreshold), maxPoolSize)
        let missing = target - ads.count

        guard missing > 0 else { return }

        loadFeedAds(count: missing)
    }
}

extension NativeAdLoader: NativeAdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        ads.append(nativeAd)
    }

    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        print("[NativeAdLoader] failed:", error.localizedDescription)
        isLoading = false
    }

    func adLoaderDidFinishLoading(_ adLoader: AdLoader) {
        isLoading = false
    }

}

private extension UIApplication {
    var currentRootViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}
