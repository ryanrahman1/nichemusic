//
//  EmailVerificationStore.swift
//  Niche Music
//

import Combine
import SwiftUI

@MainActor
final class EmailVerificationStore: ObservableObject {
    @Published private(set) var isPresented = false
    @Published var email: String = ""

    var presentationBinding: Binding<Bool> {
        Binding(
            get: { self.isPresented },
            set: { newValue in
                if !newValue {
                    self.dismiss()
                }
            }
        )
    }

    func present(email: String? = nil) {
        if let email, !email.isEmpty {
            self.email = email
        }
        FeedPlayerCache.shared.stopAll()
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }

    func handleEmailNotVerified(email: String? = nil) {
        present(email: email)
    }
}

extension APIClientError {
    var isEmailNotVerified: Bool {
        guard case .server(let statusCode, let payload) = self else { return false }
        return statusCode == 403 && payload?.code == "EMAIL_NOT_VERIFIED"
    }

    var apiErrorCode: String? {
        guard case .server(_, let payload) = self else { return nil }
        return payload?.code
    }
}
