//
//  EmailVerificationView.swift
//  Niche Music
//

import SwiftUI
import Combine

private enum EmailVerificationStep {
    case prompt
    case enterCode
    case success
}

struct EmailVerificationView: View {
    @EnvironmentObject private var emailVerification: EmailVerificationStore
    @EnvironmentObject private var session: SessionStore

    @State private var step: EmailVerificationStep = .prompt
    @State private var code = ""
    @State private var isSending = false
    @State private var isConfirming = false
    @State private var errorMessage: String?
    @State private var cooldownSeconds = 0
    @State private var expiresAt: Date?
    @State private var successScale: CGFloat = 0.6
    @State private var successOpacity: Double = 0
    @State private var shakeTrigger = 0
    @FocusState private var isCodeFocused: Bool

    private let codeLength = 6
    private let cooldownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            ambientBackground

            VStack(spacing: 0) {
                verificationBadge
                    .padding(.top, 56)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        switch step {
                        case .prompt:
                            promptContent
                        case .enterCode:
                            codeEntryContent
                                .modifier(ShakeEffect(trigger: shakeTrigger))
                        case .success:
                            successContent
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 32)
                }

                if step != .success {
                    bottomActions
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                }
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: step)
        .interactiveDismissDisabled(true)
        .onAppear {
            pauseBackgroundMedia()
            resetForPresentation()
        }
        .onChange(of: emailVerification.isPresented) { _, isPresented in
            if isPresented {
                pauseBackgroundMedia()
                resetForPresentation()
            }
        }
        .onReceive(cooldownTimer) { _ in
            guard cooldownSeconds > 0 else { return }
            cooldownSeconds -= 1
        }
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

    private var verificationBadge: some View {
        Text("Email verification")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.white.opacity(0.1), in: Capsule())
    }

    private var promptContent: some View {
        VStack(spacing: 28) {
            heroIcon(systemName: "envelope.fill")

            VStack(spacing: 12) {
                Text("Verify your email")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Confirm your email to keep listening, posting, and using the rest of Niche.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            if !emailVerification.email.isEmpty {
                emailCard
            }

            if let errorMessage {
                EmailVerificationInlineError(message: errorMessage)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private var codeEntryContent: some View {
        VStack(spacing: 28) {
            heroIcon(systemName: "number")

            VStack(spacing: 12) {
                Text("Enter your code")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("We sent a 6-digit code to \(emailVerification.email).")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            VStack(spacing: 14) {
                codeBoxes

                if let expiresAt {
                    Text("Expires \(expiresAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accentColor.opacity(0.92))
                }
            }
            .padding(20)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }

            if let errorMessage {
                EmailVerificationInlineError(message: errorMessage)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .onAppear {
            isCodeFocused = true
        }
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

                Image(systemName: "checkmark")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(Theme.accentColor)
                    .scaleEffect(successScale)
                    .opacity(successOpacity)
            }

            VStack(spacing: 10) {
                Text("Email verified")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(successOpacity)

                Text("You're all set.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .opacity(successOpacity)
            }

            Spacer(minLength: 120)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            PublishHaptics.success()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                successScale = 1
                successOpacity = 1
            }

            Task {
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                emailVerification.dismiss()
            }
        }
    }

    @ViewBuilder
    private var bottomActions: some View {
        switch step {
        case .prompt:
            Button {
                Task { await sendCode() }
            } label: {
                Group {
                    if isSending {
                        NicheProgress()
                            .frame(height: 22)
                    } else {
                        Text("Send verification code")
                            .font(.system(size: 17, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .modifier(GlassButtonModifier())
            .disabled(isSending)

        case .enterCode:
            VStack(spacing: 14) {
                Button {
                    Task { await sendCode() }
                } label: {
                    Group {
                        if isSending {
                            NicheProgress()
                                .frame(height: 18)
                        } else if cooldownSeconds > 0 {
                            Text("Resend code in \(cooldownSeconds)s")
                                .font(.system(size: 15, weight: .semibold))
                        } else {
                            Text("Resend code")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .foregroundStyle(cooldownSeconds > 0 ? .white.opacity(0.45) : Theme.accentColor)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(isSending || cooldownSeconds > 0)

                Button {
                    withAnimation {
                        step = .prompt
                        code = ""
                        errorMessage = nil
                    }
                    PublishHaptics.selection()
                } label: {
                    Text("Back")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }

        case .success:
            EmptyView()
        }
    }

    private var emailCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "at")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.accentColor)
                .frame(width: 34, height: 34)
                .background(Theme.accentColor.opacity(0.14), in: Circle())

            Text(emailVerification.email)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
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

    private var codeBoxes: some View {
        ZStack {
            HStack(spacing: 8) {
                ForEach(0..<codeLength, id: \.self) { index in
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(
                                        index == code.count ? Theme.accentColor : .white.opacity(0.12),
                                        lineWidth: index == code.count ? 1.5 : 1
                                    )
                            )
                            .frame(height: 54)

                        Text(digit(at: index))
                            .font(.system(size: 24, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .opacity(isConfirming ? 0.45 : 1)

            if isConfirming {
                NicheProgress()
            }

            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isCodeFocused)
                .opacity(0.01)
                .frame(maxWidth: .infinity, maxHeight: 54)
                .onChange(of: code) { oldValue, newValue in
                    let filtered = String(newValue.filter(\.isNumber).prefix(codeLength))
                    if filtered != newValue {
                        code = filtered
                    }

                    if filtered.count > oldValue.count {
                        PublishHaptics.selection()
                    }

                    if filtered.count == codeLength {
                        Task { await confirmCode(filtered) }
                    }
                }
        }
    }

    private func pauseBackgroundMedia() {
        FeedPlayerCache.shared.stopAll()
    }

    private func resetForPresentation() {
        step = .prompt
        code = ""
        errorMessage = nil
        isSending = false
        isConfirming = false
        cooldownSeconds = 0
        expiresAt = nil
        successScale = 0.6
        successOpacity = 0
        shakeTrigger = 0
    }

    private func digit(at index: Int) -> String {
        guard index < code.count else { return "" }
        let stringIndex = code.index(code.startIndex, offsetBy: index)
        return String(code[stringIndex])
    }

    @MainActor
    private func sendCode() async {
        guard !isSending else { return }

        isSending = true
        errorMessage = nil

        do {
            let response: EmailVerifySendResponse = try await APIClient.shared.request(
                Endpoints.emailVerifySend,
                method: .post
            )

            if response.alreadyVerified == true {
                session.markEmailVerified()
                step = .success
                return
            }

            if let expiresAtString = response.expiresAt {
                expiresAt = ISO8601DateFormatter().date(from: expiresAtString)
            }

            cooldownSeconds = response.cooldownSeconds ?? 45
            PublishHaptics.success()
            withAnimation {
                step = .enterCode
                code = ""
            }
            isCodeFocused = true
        } catch let error as APIClientError {
            handleSendError(error)
        } catch {
            errorMessage = error.localizedDescription
            PublishHaptics.error()
        }

        isSending = false
    }

    @MainActor
    private func confirmCode(_ submittedCode: String) async {
        guard !isConfirming else { return }

        isConfirming = true
        errorMessage = nil

        do {
            let response: EmailVerifyConfirmResponse = try await APIClient.shared.request(
                Endpoints.emailVerifyConfirm,
                method: .post,
                body: EmailVerifyConfirmBody(code: submittedCode)
            )

            if response.verified == true || response.alreadyVerified == true {
                session.markEmailVerified()
                withAnimation {
                    step = .success
                }
                return
            }

            errorMessage = "Could not verify that code."
            shakeAndClearCode()
        } catch let error as APIClientError {
            handleConfirmError(error)
        } catch {
            errorMessage = error.localizedDescription
            shakeAndClearCode()
        }

        isConfirming = false
    }

    private func handleSendError(_ error: APIClientError) {
        switch error.apiErrorCode {
        case "EMAIL_VERIFY_COOLDOWN":
            errorMessage = error.localizedDescription
            if step == .enterCode {
                if cooldownSeconds == 0 {
                    cooldownSeconds = 45
                }
            } else {
                withAnimation { step = .enterCode }
            }
        default:
            errorMessage = error.localizedDescription
        }
        PublishHaptics.error()
    }

    private func handleConfirmError(_ error: APIClientError) {
        switch error.apiErrorCode {
        case "EMAIL_VERIFY_INVALID_CODE":
            errorMessage = "Invalid code. Try again."
        case "EMAIL_VERIFY_TOO_MANY_ATTEMPTS":
            errorMessage = "Too many attempts. Request a new code."
            cooldownSeconds = 0
        case "EMAIL_VERIFY_CODE_EXPIRED":
            errorMessage = "That code expired. Request a new one."
            cooldownSeconds = 0
        default:
            errorMessage = error.localizedDescription
        }
        shakeAndClearCode()
    }

    private func shakeAndClearCode() {
        PublishHaptics.error()
        withAnimation(.default) {
            shakeTrigger += 1
        }
        code = ""
        isCodeFocused = true
    }
}

private struct EmailVerificationInlineError: View {
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

private struct ShakeEffect: GeometryEffect {
    var travelDistance: CGFloat = 8
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    init(trigger: Int) {
        animatableData = CGFloat(trigger)
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = travelDistance * sin(animatableData * .pi * shakesPerUnit)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
