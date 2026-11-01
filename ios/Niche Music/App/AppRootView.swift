//
//  AppRootView.swift
//  Niche Music
//

import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var emailVerification: EmailVerificationStore
    @EnvironmentObject private var messagesStore: MessagesStore
    @EnvironmentObject private var playlistStore: PlaylistStore
    @EnvironmentObject private var appNavigation: AppNavigationRouter
    @EnvironmentObject private var deepLinkCoordinator: DeepLinkCoordinator

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                LoadingView()

            case .signedOut:
                LandingPage()

            case .signedIn:
                MainTabView()
                    .ignoresSafeArea()
                    .fullScreenCover(isPresented: emailVerification.presentationBinding) {
                        EmailVerificationView()
                            .environmentObject(emailVerification)
                            .environmentObject(session)
                    }
            }
        }
        .onAppear {
            PushNotificationManager.shared.prepare()
            syncMessagesSession(with: session.state)
            configureEmailVerificationHandling()
            deepLinkCoordinator.configure(
                session: session,
                appNavigation: appNavigation,
                messagesStore: messagesStore
            )
            PushNotificationManager.shared.configure(deepLinkCoordinator: deepLinkCoordinator)
            syncPushRegistration(with: session.state)
        }
        .onChange(of: session.state) { _, newState in
            syncMessagesSession(with: newState)
            syncPushRegistration(with: newState)
            if case .signedIn = newState {
                deepLinkCoordinator.flushPendingIfAuthenticated()
            }
        }
        .onOpenURL { url in
            deepLinkCoordinator.handleIncomingURL(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            deepLinkCoordinator.handleIncomingURL(url)
        }
    }

    private func configureEmailVerificationHandling() {
        session.onNeedsEmailVerification = { email in
            emailVerification.handleEmailNotVerified(email: email)
        }

        APIClient.shared.onEmailNotVerified = { email in
            session.notifyEmailVerificationRequired(email: email ?? session.currentUser?.email)
        }
    }

    private func syncMessagesSession(with state: SessionState) {
        switch state {
        case .signedIn(let user):
            messagesStore.configure(selfUserId: user.id)
            messagesStore.start()

        case .signedOut:
            messagesStore.reset()
            playlistStore.reset()

        case .loading:
            break
        }
    }

    private func syncPushRegistration(with state: SessionState) {
        switch state {
        case .signedIn:
            PushNotificationManager.shared.setAuthenticated(true)
            PushNotificationManager.shared.syncRegistration()

        case .signedOut:
            PushNotificationManager.shared.setAuthenticated(false)

        case .loading:
            break
        }
    }
}

private struct LoadingView: View {
    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()
            NicheProgress()
        }
    }
}
