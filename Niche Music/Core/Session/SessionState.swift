//
//  SessionState.swift
//  nichemusic
//
//  Created by Ryan Rahman on 4/25/26.
//


import Foundation
import Combine

enum SessionState: Equatable {
    case loading
    case signedOut
    case signedIn(User)
}

@MainActor
final class SessionStore: ObservableObject {
    @Published var state: SessionState = .loading
    @Published var errorMessage: String?
    @Published private(set) var requiresEmailVerification = false

    var onNeedsEmailVerification: ((String?) -> Void)?

    init(bootstrap: Bool = true, previewState: SessionState? = nil) {
        if let previewState {
            self.state = previewState
            return
        }

        if bootstrap {
            Task {
                await self.bootstrap()
            }
        }
    }

    func bootstrap() async {
        do {
            let session: SessionResponse = try await APIClient.shared.request(
                Endpoints.session,
                method: .get
            )

            state = .signedIn(session.user)
            applyVerificationStatus(session.emailVerified, email: session.user.email)
        } catch {
            state = .signedOut
            requiresEmailVerification = false
        }
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil
        state = .loading

        do {
            let response: SessionResponse = try await APIClient.shared.request(
                Endpoints.loginEmail,
                method: .post,
                body: LoginBody(email: email, password: password)
            )

            state = .signedIn(response.user)
            await refreshVerificationStatus()
        } catch {
            errorMessage = error.localizedDescription
            state = .signedOut
            requiresEmailVerification = false
        }
    }

    func signUp(
        email: String,
        password: String,
        username: String,
        profileType: ProfileType,
        choseAvatar: Bool,
        avatarJPEGData: Data?
    ) async throws -> User {
        errorMessage = nil

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        let response: SignupResponse = try await APIClient.shared.request(
            Endpoints.signupEmail,
            method: .post,
            body: SignupBody(
                email: normalizedEmail,
                password: password,
                username: username,
                profileType: profileType.rawValue,
                choseAvatar: choseAvatar
            ),
            preserveBodyKeyNames: true
        )

        var avatarUrl = response.user.avatarUrl ?? ""

        if let avatarJPEGData, let upload = response.avatarUpload {
            try await uploadSignupAvatar(jpegData: avatarJPEGData, upload: upload)
            avatarUrl = upload.avatarUrl
        }

        let user = User(
            id: response.user.id,
            avatarUrl: avatarUrl,
            email: normalizedEmail
        )
        state = .signedIn(user)
        applyVerificationStatus(false, email: normalizedEmail)
        return user
    }

    func refreshVerificationStatus() async {
        do {
            let session: SessionResponse = try await APIClient.shared.request(
                Endpoints.session,
                method: .get
            )

            if case .signedIn(let user) = state {
                state = .signedIn(
                    User(
                        id: user.id,
                        avatarUrl: user.avatarUrl,
                        email: session.user.email ?? user.email
                    )
                )
            }

            applyVerificationStatus(session.emailVerified, email: session.user.email)
        } catch {
            if let apiError = error as? APIClientError, apiError.isEmailNotVerified {
                requiresEmailVerification = true
                onNeedsEmailVerification?(currentUser?.email)
            }
        }
    }

    func notifyEmailVerificationRequired(email: String?) {
        requiresEmailVerification = true
        onNeedsEmailVerification?(email ?? currentUser?.email)
    }

    func markEmailVerified() {
        requiresEmailVerification = false
    }

    func requestEmailVerification(email: String?) {
        applyVerificationStatus(false, email: email)
    }

    private func applyVerificationStatus(_ emailVerified: Bool?, email: String?) {
        let needsVerification = emailVerified == false
        requiresEmailVerification = needsVerification
        if needsVerification {
            onNeedsEmailVerification?(email ?? currentUser?.email)
        }
    }

    private func uploadSignupAvatar(jpegData: Data, upload: AvatarUploadInfo) async throws {
        guard jpegData.count <= upload.maxBytes else {
            throw SignupError.avatarTooLarge
        }

        guard let uploadURL = URL(string: upload.uploadUrl) else {
            throw SignupError.invalidUploadURL
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue(upload.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = jpegData

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw SignupError.uploadFailed
        }

        try await APIClient.shared.requestVoid(
            Endpoints.meAvatar,
            method: .patch,
            body: ConfirmAvatarBody(objectKey: upload.objectKey, avatarUrl: upload.avatarUrl),
            preserveBodyKeyNames: true
        )
    }

    func signOut() async {
        await PushNotificationManager.shared.unregisterBeforeLogout()

        do {
            try await APIClient.shared.requestVoid(Endpoints.logout, method: .post)
        } catch {
            // ignore
        }

        state = .signedOut
        requiresEmailVerification = false
    }

    var currentUser: User? {
        if case .signedIn(let user) = state {
            return user
        }
        return nil
    }

    var isAuthenticated: Bool {
        if case .signedIn = state {
            return true
        }
        return false
    }

    func updateAvatarUrl(_ avatarUrl: String) {
        guard case .signedIn(let user) = state else { return }
        state = .signedIn(User(id: user.id, avatarUrl: avatarUrl, email: user.email))
    }
}

enum SignupError: LocalizedError {
    case avatarTooLarge
    case invalidUploadURL
    case uploadFailed

    var errorDescription: String? {
        switch self {
        case .avatarTooLarge:
            return "Profile photo is too large."
        case .invalidUploadURL:
            return "Could not prepare photo upload."
        case .uploadFailed:
            return "Failed to upload profile photo."
        }
    }
}
