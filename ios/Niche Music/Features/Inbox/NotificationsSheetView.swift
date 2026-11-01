//
//  NotificationsSheetView.swift
//  Niche Music
//

import SwiftUI
import Kingfisher

private enum InboxSection: String, CaseIterable, Identifiable {
    case notifications = "Notifications"
    case requests = "Requests"

    var id: String { rawValue }
}

struct NotificationsSheetView: View {
    @ObservedObject var store: NotificationsStore
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var deepLinkCoordinator: DeepLinkCoordinator
    @Environment(\.dismiss) private var dismiss

    var onDismissAfterNavigation: (() -> Void)?

    @State private var section: InboxSection = .notifications

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundColor.ignoresSafeArea()

                VStack(spacing: 0) {
                    sectionPicker
                        .padding(.horizontal, 22)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    switch section {
                    case .notifications:
                        notificationsContent
                    case .requests:
                        followRequestsContent
                    }
                }
            }
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(.white.opacity(0.85))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if section == .notifications, store.unreadCount > 0 {
                        Button("Read all") {
                            Task { await store.markAllRead() }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accentColor)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .task {
            async let notifications: Void = store.load()
            async let requests: Void = store.loadFollowRequests()
            _ = await (notifications, requests)
        }
    }

    private var sectionPicker: some View {
        HStack(spacing: 0) {
            ForEach(InboxSection.allCases) { item in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                        section = item
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(item.rawValue)
                            .font(.system(size: 14, weight: .semibold))

                        if item == .requests, store.pendingFollowRequestCount > 0 {
                            Text("\(store.pendingFollowRequestCount)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.accentColor, in: Capsule())
                        }
                    }
                    .foregroundStyle(section == item ? .white : .white.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        section == item ? Color.white.opacity(0.1) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var notificationsContent: some View {
        if store.isLoading && store.notifications.isEmpty {
            NicheProgress()
        } else if let error = store.errorMessage, store.notifications.isEmpty {
            emptyState(
                message: error,
                actionTitle: "Try again",
                action: { Task { await store.load() } }
            )
        } else if store.notifications.isEmpty {
            emptyState(
                message: "No notifications yet",
                systemImage: "bell.slash"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.notifications) { notification in
                        notificationRow(notification)
                        Divider()
                            .overlay(Color.white.opacity(0.08))
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder
    private var followRequestsContent: some View {
        if store.isLoadingFollowRequests && store.followRequests.isEmpty {
            NicheProgress()
        } else if let error = store.followRequestsErrorMessage, store.followRequests.isEmpty {
            emptyState(
                message: error,
                actionTitle: "Try again",
                action: { Task { await store.loadFollowRequests() } }
            )
        } else if store.followRequests.isEmpty {
            emptyState(
                message: "No follow requests",
                systemImage: "person.crop.circle.badge.questionmark"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.followRequests) { request in
                        followRequestRow(request)
                        Divider()
                            .overlay(Color.white.opacity(0.08))
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private func followRequestRow(_ request: FollowRequestItem) -> some View {
        let isBusy = store.actionUserIds.contains(request.followerId)

        return HStack(spacing: 12) {
            NavigationLink {
                OtherProfileView(username: request.user.username)
            } label: {
                HStack(spacing: 12) {
                    followRequestAvatar(request.user)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(request.user.displayName ?? request.user.username)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text("@\(request.user.username)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)

                        Text(relativeDate(request.createdAt))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.38))
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button {
                    Task { await store.rejectFollowRequest(request, profileStore: profileStore) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isBusy)

                Button {
                    Task { await store.acceptFollowRequest(request, profileStore: profileStore) }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Theme.accentColor, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
            .opacity(isBusy ? 0.5 : 1)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func followRequestAvatar(_ user: FollowListProfile) -> some View {
        if let avatarUrl = user.avatarUrl, let url = URL(string: avatarUrl) {
            KFImage(url)
                .resizable()
                .scaledToFill()
        } else {
            Circle()
                .fill(.white.opacity(0.08))
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
        }
    }

    private func notificationRow(_ notification: AppNotification) -> some View {
        Button {
            Task {
                await store.markRead(notification)
                deepLinkCoordinator.handleNotification(notification)
                dismiss()
                onDismissAfterNavigation?()
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                notificationImage(notification)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(notification.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if !notification.isRead {
                            Circle()
                                .fill(Theme.accentColor)
                                .frame(width: 6, height: 6)
                        }
                    }

                    Text(notification.body)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(relativeDate(notification.createdAt))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.38))
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(notification.isRead ? Color.clear : Color.white.opacity(0.03))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func emptyState(
        message: String,
        systemImage: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }

            Text(message)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func notificationImage(_ notification: AppNotification) -> some View {
        if let imageUrl = notification.imageUrl, let url = URL(string: imageUrl) {
            KFImage(url)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay {
                    Image(systemName: iconName(for: notification.kind))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
        }
    }

    private func iconName(for kind: String) -> String {
        switch kind {
        case "message": return "message.fill"
        case "follow", "follow_accept": return "person.fill"
        case "post_like", "comment_like", "track_comment_like": return "heart.fill"
        case "post_comment", "comment_reply", "track_comment", "track_comment_reply": return "text.bubble.fill"
        default: return "bell.fill"
        }
    }

    private func relativeDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: iso)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: iso)
        }
        guard let date else { return "" }

        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}
