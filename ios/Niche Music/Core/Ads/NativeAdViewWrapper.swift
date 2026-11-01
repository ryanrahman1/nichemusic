//
//  NativeAdViewWrapper.swift
//  Niche Music
//
//  Created by Ryan Rahman on 6/1/26.
//

import SwiftUI
import GoogleMobileAds

struct FeedNativeAdPageView: UIViewRepresentable {
    let nativeAd: NativeAd

    func makeUIView(context: Context) -> NativeAdView {
        let adView = NativeAdView()
        adView.backgroundColor = .black

        let mediaView = MediaView() 
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        mediaView.contentMode = .scaleAspectFill
        mediaView.clipsToBounds = true

        let headlineLabel = UILabel()
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false
        headlineLabel.textColor = .white
        headlineLabel.font = .systemFont(ofSize: 26, weight: .semibold)
        headlineLabel.numberOfLines = 2

        let bodyLabel = UILabel()
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        bodyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        bodyLabel.numberOfLines = 3

        let adLabel = UILabel()
        adLabel.translatesAutoresizingMaskIntoConstraints = false
        adLabel.text = "Ad"
        adLabel.textColor = .black
        adLabel.backgroundColor = .white
        adLabel.font = .systemFont(ofSize: 11, weight: .bold)
        adLabel.textAlignment = .center
        adLabel.layer.cornerRadius = 4
        adLabel.clipsToBounds = true

        let ctaLabel = UILabel()
        ctaLabel.translatesAutoresizingMaskIntoConstraints = false
        ctaLabel.textColor = .white
        ctaLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        ctaLabel.textAlignment = .center
        ctaLabel.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        ctaLabel.layer.borderWidth = 1
        ctaLabel.layer.cornerRadius = 14
        ctaLabel.clipsToBounds = true

        adView.addSubview(mediaView)
        adView.addSubview(headlineLabel)
        adView.addSubview(bodyLabel)
        adView.addSubview(adLabel)
        adView.addSubview(ctaLabel)

        adView.mediaView = mediaView
        adView.headlineView = headlineLabel
        adView.bodyView = bodyLabel
        adView.callToActionView = ctaLabel

        NSLayoutConstraint.activate([
            mediaView.topAnchor.constraint(equalTo: adView.topAnchor),
            mediaView.leadingAnchor.constraint(equalTo: adView.leadingAnchor),
            mediaView.trailingAnchor.constraint(equalTo: adView.trailingAnchor),
            mediaView.bottomAnchor.constraint(equalTo: adView.bottomAnchor),

            adLabel.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 22),
            adLabel.bottomAnchor.constraint(equalTo: headlineLabel.topAnchor, constant: -12),
            adLabel.widthAnchor.constraint(equalToConstant: 34),
            adLabel.heightAnchor.constraint(equalToConstant: 20),

            headlineLabel.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 22),
            headlineLabel.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -22),
            headlineLabel.bottomAnchor.constraint(equalTo: bodyLabel.topAnchor, constant: -8),

            bodyLabel.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 22),
            bodyLabel.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -22),
            bodyLabel.bottomAnchor.constraint(equalTo: ctaLabel.topAnchor, constant: -18),

            ctaLabel.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 22),
            ctaLabel.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -22),
            ctaLabel.bottomAnchor.constraint(equalTo: adView.safeAreaLayoutGuide.bottomAnchor, constant: -92),
            ctaLabel.heightAnchor.constraint(equalToConstant: 48)
        ])

        return adView
    }

    func updateUIView(_ adView: NativeAdView, context: Context) {
        (adView.headlineView as? UILabel)?.text = nativeAd.headline
        (adView.bodyView as? UILabel)?.text = nativeAd.body
        (adView.callToActionView as? UILabel)?.text = nativeAd.callToAction ?? "Learn More"

        adView.mediaView?.mediaContent = nativeAd.mediaContent
        adView.nativeAd = nativeAd

        // Important: CTA view should not handle touches itself.
        adView.callToActionView?.isUserInteractionEnabled = false
    }
}
