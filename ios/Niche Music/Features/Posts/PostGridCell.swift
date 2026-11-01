//
//  PostGridCell.swift
//  Niche Music
//
//  Created by Ryan Rahman on 6/1/26.
//


import SwiftUI
import Kingfisher

struct PostGridCell: View {
    let post: Post
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            thumbnail
                .frame(width: width, height: height)
                .clipped()

            if post.isVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.75), radius: 4)
                    .padding(7)
            } else if post.showsMusicBadge {
                Image(systemName: "music.note")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.75), radius: 4)
                    .padding(7)
            }
        }
        .frame(width: width, height: height)
        .background(.white.opacity(0.04))
        .clipped()
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = post.thumbnailURL {
            KFImage(url)
                // Downsample to the exact display size via ImageIO — avoids decoding
                // a full-res photo into a tiny grid cell, cutting memory & GPU work ~10×.
                .setProcessor(
                    DownsamplingImageProcessor(
                        size: CGSize(width: width * UIScreen.main.scale,
                                     height: height * UIScreen.main.scale)
                    )
                )
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(.white.opacity(0.06))
                .overlay {
                    Image(systemName: "text.alignleft")
                        .foregroundStyle(.white.opacity(0.35))
                }
        }
    }
}
