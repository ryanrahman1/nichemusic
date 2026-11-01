//
//  FeedBottomBar.swift
//  Niche Music
//
//  Created by Ryan Rahman on 6/1/26.
//


import SwiftUI

struct FeedBottomBar: View {
    let likeCount: Int
    let commentCount: Int
    let repostCount: Int

    let isLiked: Bool
    let isReposted: Bool

    let onComment: () -> Void
    let onLike: () -> Void
    let onRepost: () -> Void

    var body: some View {
        HStack {
            feedAction(
                icon: "bubble.left",
                filledIcon: "bubble.left.fill",
                count: commentCount,
                active: false,
                action: onComment
            )

            Spacer()

            feedAction(
                icon: "heart",
                filledIcon: "heart.fill",
                count: likeCount,
                active: isLiked,
                action: onLike
            )

            Spacer()

            feedAction(
                icon: "arrow.2.squarepath",
                filledIcon: "arrow.2.squarepath",
                count: repostCount,
                active: isReposted,
                action: onRepost
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 13)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func feedAction(
        icon: String,
        filledIcon: String,
        count: Int,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: active ? filledIcon : icon)
                    .font(.system(size: 19, weight: .semibold))

                Text("\(count)")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(active ? .white : .white.opacity(0.76))
            .frame(minWidth: 70)
        }
        .buttonStyle(.plain)
    }
}
