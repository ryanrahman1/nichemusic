//
//  MomentVideoBackground.swift
//  Niche Music
//
//  Created by Ryan Rahman on 5/24/26.
//


//
//  MomentVideoBackground.swift
//  nichemusic
//
//  Created by Ryan Rahman on 5/15/26.
//


import SwiftUI
import AVFoundation

struct MomentVideoBackground: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }
    }
}