//
//  ForgotPasswordView.swift
//  Niche Music
//

import SwiftUI

private enum ForgotPasswordStep {
    case enterEmail
    case success
}

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss

    let initialEmail: String

    @State private var step: ForgotPasswordStep = .enterEmail
    @State private var email: String
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var successScale: CGFloat = 0.6
    @State private var successOpacity: Double = 0
    @FocusState private var isEmailFocused: Bool

    init(initialEmail: String = "") {
        self.initialEmail = initialEmail
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        ZStack {
            ambientBackground

            VStack(spacing: 0) {
                topBar

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        switch step {
                        case .enterEmail:
                            enterEmailContent
                        case .success:
                            successContent
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 32)
                }

                if step == .enterEmail {
                    bottomActions
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                }
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: step)
        .onAppear {
            if email.isEmpty {
                isEmailFocused = true
            }
        }
    }

    private var topBar: some View {
        HStack {
            if step == .enterEmail {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 36, height: 36)
            }

            Spacer()

            Text("Password reset")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.white.opacity(0.1), in: Capsule())

            Spacer()

            if step == .enterEmail {
                Button("Cancel") { dismiss() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            } else {
                Color.clear.frame(width: 52, height: 36)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var enterEmailContent: some View {
        VStack(spacing: 28) {
            heroIcon(systemName: "lock.rotation")

            VStack(spacing: 12) {
                Text("Reset your password")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Enter the email for your account and we'll send you a link to choose a new password.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            TextField("Email", text: $email)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isEmailFocused)
                .padding()
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if !email.isEmpty && !isEmailValid {
                ForgotPasswordInlineError(message: "Enter a valid email address.")
            }

            if let errorMessage {
                ForgotPasswordInlineError(message: errorMessage)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private var successContent: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 80)

            ZStack {
                Circle()
                    .fill(Theme.accentColor.opacity(0.2))
                    .frame(width: 132, height: 132)
                    .blur(radius: 8)

                Circle()
                    .fill(Theme.accentColor.opacity(0.16))
                    .frame(width: 112, height: 112)

                Image(systemName: "envelope.badge")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)
                    .scaleEffect(successScale)
                    .opacity(successOpacity)
            }

            VStack(spacing: 12) {
                Text("Check your email")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(successOpacity)

                Text("If an account exists for \(trimmedEmail), you'll get a reset link shortly. Open it in your browser to set a new password.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .opacity(successOpacity)
            }
            .padding(.horizontal, 8)

            Button {
                dismiss()
            } label: {
                Text("Back to log in")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .modifier(GlassButtonModifier())
            .opacity(successOpacity)
            .padding(.top, 12)

            Spacer(minLength: 120)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            PublishHaptics.success()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                successScale = 1
                successOpacity = 1
            }
        }
    }

    private var bottomActions: some View {
        Button {
            Task { await sendResetLink() }
        } label: {
            Group {
                if isSending {
                    NicheProgress()
                        .frame(height: 22)
                } else {
                    Text("Send reset link")
                        .font(.system(size: 17, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
        }
        .modifier(GlassButtonModifier())
        .disabled(isSending || !isEmailValid)
        .opacity(isEmailValid ? 1 : 0.55)
    }

    private var ambientBackground: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()

            Circle()
                .fill(Theme.accentColor.opacity(0.24))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: -120, y: -260)

            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: 140, y: 220)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.15),
                    Color.black.opacity(0.82),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private func heroIcon(systemName: String) -> some View {
        ZStack {
            Circle()
                .fill(Theme.accentColor.opacity(0.18))
                .frame(width: 108, height: 108)

            Circle()
                .strokeBorder(Theme.accentColor.opacity(0.35), lineWidth: 1.5)
                .frame(width: 108, height: 108)

            Image(systemName: systemName)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(height: 120)
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isEmailValid: Bool {
        let trimmed = trimmedEmail
        guard !trimmed.isEmpty else { return false }
        return trimmed.contains("@") && trimmed.contains(".") && trimmed.count >= 5
    }

    @MainActor
    private func sendResetLink() async {
        guard !isSending, isEmailValid else { return }

        isSending = true
        errorMessage = nil
        isEmailFocused = false

        do {
            let _: PasswordResetSendResponse = try await APIClient.shared.request(
                Endpoints.passwordResetSend,
                method: .post,
                body: PasswordResetSendBody(email: trimmedEmail)
            )

            PublishHaptics.success()
            withAnimation {
                step = .success
            }
        } catch let error as APIClientError {
            errorMessage = error.localizedDescription
            PublishHaptics.error()
        } catch {
            errorMessage = error.localizedDescription
            PublishHaptics.error()
        }

        isSending = false
    }
}

private struct ForgotPasswordInlineError: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.red.opacity(0.88))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
    }
}

#Preview {
    ForgotPasswordView(initialEmail: "you@example.com")
}
