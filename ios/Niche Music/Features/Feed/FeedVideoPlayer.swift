//
//  FeedVideoPlayerf.swift
//  Niche Music
//
//  Created by Ryan Rahman on 6/1/26.
//

import SwiftUI
import AVKit

final class LoopingPlayerView: UIView {
    private var loopObserver: Any?

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayerRef: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    func configure(with player: AVPlayer, contentMode: FeedVideoContentMode) {
        playerLayerRef.player = player
        playerLayerRef.videoGravity = contentMode.videoGravity
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayerRef.frame = bounds
    }
}

enum FeedVideoContentMode {
    case fill
    case fit

    var videoGravity: AVLayerVideoGravity {
        switch self {
        case .fill:
            return .resizeAspectFill
        case .fit:
            return .resizeAspect
        }
    }
}

struct FeedVideoPlayer: UIViewRepresentable {
    let player: AVPlayer
    var contentMode: FeedVideoContentMode = .fill

    func makeUIView(context: Context) -> LoopingPlayerView {
        let view = LoopingPlayerView()
        view.configure(with: player, contentMode: contentMode)
        return view
    }

    func updateUIView(_ uiView: LoopingPlayerView, context: Context) {
        uiView.configure(with: player, contentMode: contentMode)
    }
}
