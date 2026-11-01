//
//  SignupFlowView.swift
//  Niche Music
//

import PhotosUI
import SwiftUI
import UIKit

enum SignupStep: Int, CaseIterable {
    case emailPassword
    case dateOfBirth
    case username
    case role
    case avatar
    case terms
    case creating

    var progressIndex: Int {
        switch self {
        case .emailPassword: 1
        case .dateOfBirth: 2
        case .username: 3
        case .role: 4
        case .avatar: 5
        case .terms: 6
        case .creating: 7
        }
    }

    static let progressTotal = 6
}

enum UsernameAvailabilityState: Equatable {
    case idle
    case checking
    case available
    case taken
    case invalid(String)
}

struct SignupDraft {
    var email = ""
    var password = ""
    var dateOfBirth = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    var username = ""
    var profileType: ProfileType = .user
    var avatarJPEGData: Data?
    var agreedToTerms = false
}

struct SignupFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    @State private var step: SignupStep = .emailPassword
    @State private var draft = SignupDraft()
    @State private var usernameState: UsernameAvailabilityState = .idle
    @State private var usernameCheckTask: Task<Void, Never>?
    @State private var creationMessageIndex = 0
    @State private var signupError: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var avatarPreviewImage: UIImage?
    @State private var isUploadingAvatar = false

    private let creationMessages = [
        "Setting up your profile",
        "Tuning your feed",
        "Welcome to Niche"
    ]

    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        stepContent
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: step)
        .onChange(of: draft.username) { _, newValue in
            scheduleUsernameCheck(for: newValue)
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task { await loadSelectedPhoto(from: newItem) }
        }
        .onChange(of: step) { _, newStep in
            if newStep == .creating {
                startCreatingAccount()
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            if step != .creating {
                Button {
                    goBack()
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

            if step != .creating {
                SignupProgressBar(
                    progress: Double(step.progressIndex) / Double(SignupStep.progressTotal)
                )
            } else {
                SignupProgressBar(progress: 1)
            }

            if step != .creating {
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

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .emailPassword:
            emailPasswordStep
        case .dateOfBirth:
            dateOfBirthStep
        case .username:
            usernameStep
        case .role:
            roleStep
        case .avatar:
            avatarStep
        case .terms:
            termsStep
        case .creating:
            creatingStep
        }
    }

    private var emailPasswordStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            SignupTitle(
                title: "Let's get you in",
                subtitle: "Create your account with email and a secure password."
            )

            VStack(spacing: 12) {
                SignupField("Email", text: $draft.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)

                PasswordField(
                    placeholder: "Password",
                    password: $draft.password,
                    textContentType: .newPassword
                )
            }

            if !draft.password.isEmpty && !isPasswordValid {
                SignupInlineError(
                    "Use at least 8 characters with one uppercase letter and one number."
                )
            }

            if !draft.email.isEmpty && !isEmailValid {
                SignupInlineError("Enter a valid email address.")
            }

            SignupPrimaryButton(title: "Continue", isEnabled: canContinueFromEmailPassword) {
                advance(from: .emailPassword)
            }
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var dateOfBirthStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            SignupTitle(
                title: "When were you born?",
                subtitle: "We only use this to confirm you're old enough to use Niche."
            )

            DatePicker(
                "Date of birth",
                selection: $draft.dateOfBirth,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .colorScheme(.dark)
            .tint(Theme.accentColor)

            if !isAgeValid {
                SignupInlineError("You must be at least 13 to use Niche Music.")
            }

            SignupPrimaryButton(title: "Continue", isEnabled: isAgeValid) {
                advance(from: .dateOfBirth)
            }
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var usernameStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            SignupTitle(
                title: "Choose your username",
                subtitle: "This is how people will find you on Niche."
            )

            SignupField("Username", text: $draft.username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: draft.username) { _, newValue in
                    let filtered = SignupValidation.filteredUsername(newValue)
                    if filtered != newValue {
                        draft.username = filtered
                    }
                }

            Text("@\(draft.username.isEmpty ? "username" : draft.username.lowercased())")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))

            usernameAvailabilityLabel

            SignupPrimaryButton(title: "Continue", isEnabled: canContinueFromUsername) {
                draft.username = draft.username.lowercased()
                advance(from: .username)
            }
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    @ViewBuilder
    private var usernameAvailabilityLabel: some View {
        switch usernameState {
        case .idle:
            EmptyView()
        case .checking:
            Text("Checking…")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        case .available:
            Text("Available")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.green)
        case .taken:
            Text("Taken")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.red.opacity(0.85))
        case .invalid(let message):
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.red.opacity(0.85))
        }
    }

    private var roleStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            SignupTitle(
                title: "How will you use Niche?",
                subtitle: "Pick your primary role. You can change this later, but not often."
            )

            VStack(spacing: 12) {
                ForEach(ProfileType.signupOrder, id: \.self) { type in
                    SignupRoleCard(
                        type: type,
                        isSelected: draft.profileType == type
                    ) {
                        draft.profileType = type
                        haptic(.light)
                    }
                }
            }

            SignupPrimaryButton(title: "Continue", isEnabled: true) {
                advance(from: .role)
            }
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var avatarStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            SignupTitle(
                title: "Add a profile photo",
                subtitle: "Optional — you can always add one later."
            )

            HStack {
                Spacer()
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 132, height: 132)

                    if let avatarPreviewImage {
                        Image(uiImage: avatarPreviewImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 132, height: 132)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 44, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                    }

                    if isUploadingAvatar {
                        Circle()
                            .fill(Color.black.opacity(0.45))
                            .frame(width: 132, height: 132)
                        ProgressView()
                            .tint(.white)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 8)

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Text("Choose photo")
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .modifier(GlassButtonModifier())

            Button("Skip for now") {
                draft.avatarJPEGData = nil
                avatarPreviewImage = nil
                advance(from: .avatar)
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.65))
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)

            if draft.avatarJPEGData != nil {
                SignupPrimaryButton(title: "Continue", isEnabled: !isUploadingAvatar) {
                    advance(from: .avatar)
                }
            }
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var termsStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            SignupTitle(
                title: "Almost done",
                subtitle: "Review and agree to continue."
            )

            Text("By creating an account, you agree to Niche Music's Terms of Service and Privacy Policy.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
                .lineSpacing(3)

            Toggle(isOn: $draft.agreedToTerms) {
                Text("I agree to the Terms and Privacy Policy")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .toggleStyle(SwitchToggleStyle(tint: Theme.accentColor))

            HStack(spacing: 16) {
                Link("Terms of Service", destination: URL(string: "https://nichemusic.app/terms")!)
                Link("Privacy Policy", destination: URL(string: "https://nichemusic.app/privacy")!)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.accentColor)

            if let errorMessage = signupError {
                SignupInlineError(errorMessage)
            }

            SignupPrimaryButton(title: "Create account", isEnabled: draft.agreedToTerms) {
                advance(from: .terms)
            }
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var creatingStep: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 80)

            NicheProgress()

            Text(creationMessages[creationMessageIndex])
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.45), value: creationMessageIndex)

            if let errorMessage = signupError {
                SignupInlineError(errorMessage)

                SignupPrimaryButton(title: "Try again", isEnabled: true) {
                    signupError = nil
                    step = .terms
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }

    private var isEmailValid: Bool {
        SignupValidation.isValidEmail(draft.email)
    }

    private var isPasswordValid: Bool {
        SignupValidation.isValidPassword(draft.password)
    }

    private var canContinueFromEmailPassword: Bool {
        isEmailValid && isPasswordValid
    }

    private var isAgeValid: Bool {
        SignupValidation.isAtLeast13(draft.dateOfBirth)
    }

    private var canContinueFromUsername: Bool {
        usernameState == .available
    }

    private func goBack() {
        haptic(.light)
        switch step {
        case .emailPassword:
            dismiss()
        case .dateOfBirth:
            step = .emailPassword
        case .username:
            step = .dateOfBirth
        case .role:
            step = .username
        case .avatar:
            step = .role
        case .terms:
            step = .avatar
        case .creating:
            step = .terms
        }
    }

    private func advance(from current: SignupStep) {
        haptic(.medium)
        switch current {
        case .emailPassword:
            step = .dateOfBirth
        case .dateOfBirth:
            step = .username
        case .username:
            step = .role
        case .role:
            step = .avatar
        case .avatar:
            step = .terms
        case .terms:
            step = .creating
        case .creating:
            break
        }
    }

    private func scheduleUsernameCheck(for raw: String) {
        usernameCheckTask?.cancel()
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized.isEmpty {
            usernameState = .idle
            return
        }

        if let message = SignupValidation.usernameValidationMessage(normalized) {
            usernameState = .invalid(message)
            return
        }

        usernameState = .checking

        usernameCheckTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }

            do {
                let response: UsernameAvailabilityResponse = try await APIClient.shared.request(
                    Endpoints.signupUsernameAvailable,
                    method: .get,
                    query: ["username": normalized]
                )

                guard !Task.isCancelled else { return }

                if response.available {
                    usernameState = .available
                } else if response.reason == "invalid" {
                    usernameState = .invalid(response.message ?? "Invalid username")
                } else {
                    usernameState = .taken
                }
            } catch {
                guard !Task.isCancelled else { return }
                usernameState = .invalid("Couldn't check username")
            }
        }
    }

    private func loadSelectedPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }

        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: data),
            let jpeg = ArtworkImageProcessing.uploadJPEG(from: image)
        else {
            signupError = "Couldn't process that photo."
            return
        }

        avatarPreviewImage = UIImage(data: jpeg)
        draft.avatarJPEGData = jpeg
        signupError = nil
        haptic(.light)
    }

    private func startCreatingAccount() {
        creationMessageIndex = 0
        signupError = nil

        Task {
            for index in 1..<creationMessages.count {
                try? await Task.sleep(nanoseconds: 900_000_000)
                creationMessageIndex = index
            }

            do {
                _ = try await session.signUp(
                    email: draft.email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: draft.password,
                    username: draft.username.lowercased(),
                    profileType: draft.profileType,
                    choseAvatar: draft.avatarJPEGData != nil,
                    avatarJPEGData: draft.avatarJPEGData
                )
                haptic(.success)
            } catch {
                signupError = error.localizedDescription
                haptic(.error)
            }
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

private enum SignupValidation {
    static func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.contains("@") && trimmed.contains(".") && trimmed.count >= 5
    }

    static func isValidPassword(_ password: String) -> Bool {
        password.count >= 8
            && password.range(of: "[A-Z]", options: .regularExpression) != nil
            && password.range(of: "[0-9]", options: .regularExpression) != nil
    }

    static func isAtLeast13(_ date: Date) -> Bool {
        guard let minimum = Calendar.current.date(byAdding: .year, value: -13, to: Date()) else {
            return false
        }
        return date <= minimum
    }

    static func filteredUsername(_ value: String) -> String {
        let lower = value.lowercased()
        return lower.filter { char in
            char.isLowercase || char.isNumber || char == "_" || char == "."
        }
    }

    static func usernameValidationMessage(_ username: String) -> String? {
        if username.count < 3 { return "Username must be at least 3 characters" }
        if username.count > 30 { return "Username must be at most 30 characters" }
        if username.range(of: "^[a-z0-9_.]+$", options: .regularExpression) == nil {
            return "Use letters, numbers, underscores, and periods only"
        }
        return nil
    }
}

private struct SignupTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
                .lineSpacing(2)
        }
    }
}

private struct SignupField: View {
    let placeholder: String
    @Binding var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.white)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding()
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SignupInlineError: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.red.opacity(0.85))
    }
}

private struct SignupPrimaryButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.bold)
                .foregroundColor(.white.opacity(isEnabled ? 1 : 0.45))
                .frame(maxWidth: .infinity)
                .padding()
        }
        .modifier(GlassButtonModifier())
        .disabled(!isEnabled)
        .padding(.top, 4)
    }
}

private struct SignupProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(Theme.accentColor)
                    .frame(width: geometry.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 4)
    }
}

private struct SignupRoleCard: View {
    let type: ProfileType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(type.formattedLabel)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(type.signupSubtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.accentColor : .white.opacity(0.28))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Theme.accentColor.opacity(0.14) : Color.white.opacity(0.08))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Theme.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SignupFlowView()
        .environmentObject(SessionStore(bootstrap: false, previewState: .signedOut))
}
