//
//  PlayerLayerView.swift
//  Niche Music
//
//  Created by Ryan Rahman on 5/24/26.
//


//
//  PlayerLayerView.swift
//  nichemusic
//
//  Created by Ryan Rahman on 5/1/26.
//


import SwiftUI
import AVFoundation

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }
}

final class PlayerUIView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}