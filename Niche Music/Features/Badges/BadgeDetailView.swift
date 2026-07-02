//
//  BadgeDetailView.swift
//  Niche Music
//

import Kingfisher
import SwiftUI

struct BadgeDetailView: View {
    let badgeId: String
    var initialBadge: BadgeDetail?

    @StateObject private var store: BadgeStore

    init(badgeId: String, initialBadge: BadgeDetail? = nil) {
        self.badgeId = badgeId
        self.initialBadge = initialBadge
        _store = StateObject(wrappedValue: BadgeStore(badgeId: badgeId))
    }

    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()

            if store.isLoadingBadge && store.badge == nil {
                ProgressView()
                    .tint(.white)
            } else if let error = store.errorMessage, store.badge == nil {
                errorView(error)
            } else {
                content
            }
        }
        .navigationTitle(store.badge?.text ?? "Badge")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await store.load(initialPreview: initialBadge)
        }
        .refreshable {
            await store.refresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                if let badge = store.badge {
                    BadgeHeroView(badge: badge)
                        .padding(.bottom, 8)
                }

                if store.isLoadingHolders && store.holders.isEmpty {
                    ProgressView()
                        .tint(.white)
                        .padding(.vertical, 32)
                } else if store.holders.isEmpty {
                    if (store.badge?.holderCount ?? 0) > 0 {
                        holdersLoadErrorView
                    } else {
                        Text("No one has this badge yet.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.vertical, 32)
                    }
                } else {
                    ForEach(store.holders) { holder in
                        ProfileUsernameLink(username: holder.username) {
                            holderRow(holder)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            Task { await store.loadMoreIfNeeded(currentHolder: holder) }
                        }
                    }

                    if store.isLoadingMoreHolders {
                        ProgressView()
                            .tint(.white)
                            .padding(.vertical, 16)
                    }
                }
            }
            .padding(.bottom, 120)
        }
    }

    private func holderRow(_ holder: BadgeHolder) -> some View {
        HStack(spacing: 14) {
            holderAvatar(holder)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(holder.displayTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                Text("@\(holder.username)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func holderAvatar(_ holder: BadgeHolder) -> some View {
        if let avatarUrl = holder.avatarUrl, let url = URL(string: avatarUrl) {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            Circle()
                .fill(.white.opacity(0.08))
                .overlay {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.white.opacity(0.35))
                }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Button("Try Again") {
                Task { await store.refresh() }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
        }
    }

    private var holdersLoadErrorView: some View {
        VStack(spacing: 14) {
            Text(store.errorMessage ?? "Couldn't load badge holders.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Button("Try Again") {
                Task { await store.refresh() }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.vertical, 32)
    }
}

#Preview {
    NavigationStack {
        BadgeDetailView(
            badgeId: "preview",
            initialBadge: BadgeDetail(
                id: "preview",
                text: "CEO",
                colorHex: "ffbb00",
                createdAt: nil,
                holderCount: 12
            )
        )
    }
}
