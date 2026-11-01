//
//  PushNotificationManager.swift
//  Niche Music
//

import Foundation
import UIKit
import UserNotifications

@MainActor
final class PushNotificationManager: NSObject {
    static let shared = PushNotificationManager()

    private enum Storage {
        static let deviceTokenKey = "push.deviceToken"
    }

    private var deepLinkCoordinator: DeepLinkCoordinator?
    private var coldStartPayload: [AnyHashable: Any]?
    private var isAuthenticated = false
    private var registerInFlight = false

    func prepare() {
        UNUserNotificationCenter.current().delegate = self
    }

    func configure(deepLinkCoordinator: DeepLinkCoordinator) {
        self.deepLinkCoordinator = deepLinkCoordinator
        if let coldStartPayload {
            self.coldStartPayload = nil
            deepLinkCoordinator.handlePushPayload(coldStartPayload)
        }
    }

    func storeColdStartPayload(_ userInfo: [AnyHashable: Any]) {
        coldStartPayload = userInfo
    }

    func setAuthenticated(_ authenticated: Bool) {
        isAuthenticated = authenticated
    }

    /// Mirrors RN `registerPushDevice()` — request permission, register with APNs, then POST token to API.
    func syncRegistration() {
        guard isAuthenticated, !registerInFlight else { return }
        registerInFlight = true

        Task {
            defer { registerInFlight = false }
            let granted = await requestAuthorizationIfNeeded()
            guard granted else { return }

            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }

            if let token = storedDeviceToken() {
                await registerDeviceTokenWithAPI(token)
            }
        }
    }

    func handleDeviceToken(_ deviceToken: Data) {
        let token = formattedDeviceToken(deviceToken)
        guard !token.isEmpty else { return }

        persistDeviceToken(token)

        guard isAuthenticated else { return }

        Task {
            await registerDeviceTokenWithAPI(token)
        }
    }

    func handleRegistrationFailure(_ error: Error) {
        print("[PushNotificationManager] APNs registration failed: \(error.localizedDescription)")
    }

    /// Mirrors RN `unregisterPushDevice()` — call before logout while the session is still valid.
    func unregisterBeforeLogout() async {
        guard let token = storedDeviceToken() else { return }

        do {
            try await APIClient.shared.requestVoid(
                Endpoints.deletePushDevice,
                method: .post,
                body: DeletePushDeviceRequest(deviceToken: token),
                preserveBodyKeyNames: true
            )
        } catch {
            print("[PushNotificationManager] unregister failed: \(error.localizedDescription)")
        }

        clearStoredDeviceToken()
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func registerDeviceTokenWithAPI(_ token: String) async {
        guard isAuthenticated else { return }

        let bundleId = Bundle.main.bundleIdentifier ?? "com.nichemusic.app"

        do {
            try await APIClient.shared.requestVoid(
                Endpoints.registerPushDevice,
                method: .post,
                body: RegisterPushDeviceRequest(
                    platform: "ios",
                    environment: pushEnvironment,
                    deviceToken: token,
                    appBundleId: bundleId,
                    deviceName: UIDevice.current.name
                ),
                preserveBodyKeyNames: true
            )
        } catch {
            print("[PushNotificationManager] register failed: \(error.localizedDescription)")
        }
    }

    private var pushEnvironment: String {
        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
    }

    private func formattedDeviceToken(_ deviceToken: Data) -> String {
        deviceToken.map { String(format: "%02x", $0) }.joined()
    }

    private func storedDeviceToken() -> String? {
        UserDefaults.standard.string(forKey: Storage.deviceTokenKey)
    }

    private func persistDeviceToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: Storage.deviceTokenKey)
    }

    private func clearStoredDeviceToken() {
        UserDefaults.standard.removeObject(forKey: Storage.deviceTokenKey)
    }
}

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        await MainActor.run {
            deepLinkCoordinator?.handlePushPayload(userInfo)
        }
    }
}

private struct RegisterPushDeviceRequest: Encodable {
    let platform: String
    let environment: String
    let deviceToken: String
    let appBundleId: String
    let deviceName: String?
}

private struct DeletePushDeviceRequest: Encodable {
    let deviceToken: String
}
