//
//  NotificationsStore.swift
//  Niche Music
//

import Foundation
import Combine

@MainActor
final class NotificationsStore: ObservableObject {
    @Published private(set) var notifications: [AppNotification] = []
    @Published private(set) var followRequests: [FollowRequestItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingFollowRequests = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var followRequestsErrorMessage: String?
    @Published private(set) var actionUserIds: Set<String> = []

    private let api = APIClient.shared

    var unreadCount: Int {
        notifications.filter { !$0.isRead }.count
    }

    var pendingFollowRequestCount: Int {
        followRequests.count
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            let response: NotificationsListResponse = try await api.request(
                Endpoints.myNotifications,
                method: .get
            )
            notifications = response.notifications
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadFollowRequests() async {
        isLoadingFollowRequests = true
        followRequestsErrorMessage = nil

        do {
            let response: FollowRequestsResponse = try await api.request(
                Endpoints.myFollowRequests,
                method: .get
            )
            followRequests = response.followRequests
        } catch {
            followRequestsErrorMessage = error.localizedDescription
        }

        isLoadingFollowRequests = false
    }

    func acceptFollowRequest(_ request: FollowRequestItem, profileStore: ProfileStore) async {
        guard !actionUserIds.contains(request.followerId) else { return }
        actionUserIds.insert(request.followerId)
        defer { actionUserIds.remove(request.followerId) }

        do {
            try await profileStore.acceptFollowRequest(userId: request.followerId)
            followRequests.removeAll { $0.followerId == request.followerId }
        } catch {
            followRequestsErrorMessage = error.localizedDescription
        }
    }

    func rejectFollowRequest(_ request: FollowRequestItem, profileStore: ProfileStore) async {
        guard !actionUserIds.contains(request.followerId) else { return }
        actionUserIds.insert(request.followerId)
        defer { actionUserIds.remove(request.followerId) }

        do {
            try await profileStore.rejectFollowRequest(userId: request.followerId)
            followRequests.removeAll { $0.followerId == request.followerId }
        } catch {
            followRequestsErrorMessage = error.localizedDescription
        }
    }

    func markRead(_ notification: AppNotification) async {
        guard !notification.isRead else { return }

        do {
            let response: NotificationReadResponse = try await api.request(
                Endpoints.markNotificationRead(id: notification.id),
                method: .post
            )
            if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
                notifications[index] = response.notification
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markAllRead() async {
        do {
            try await api.requestVoid(
                Endpoints.markAllNotificationsRead,
                method: .post
            )
            notifications = notifications.map { $0.markedRead() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
