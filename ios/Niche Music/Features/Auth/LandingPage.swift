//
//  ContentView.swift
//  Niche Music
//
//  Created by Ryan Rahman on 5/23/26.
//

import SwiftUI
import Combine

enum AuthMode: Equatable {
    case login
}

struct LandingPage: View {
    @State private var authMode: AuthMode?
    @State private var showSignupFlow = false
    @State private var showForgotPassword = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var showInfo = false
    @EnvironmentObject var session: SessionStore

    @State private var email = ""
    @State private var password = ""

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                Color.black.ignoresSafeArea()

                Image("hero")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .ignoresSafeArea()
                    .offset(x: geometry.size.width * 1.4)
                    .clipped()
                    .blur(radius: authMode == nil ? 0 : 12)
                    .overlay(Color.black.opacity(authMode == nil ? 0 : 0.38))

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.95),
                        Color.black.opacity(0.55),
                        Color.clear
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .ignoresSafeArea()

                VStack {
                    HStack {
                        Spacer()

                        Button {
                            showInfo.toggle()
                        } label: {
                            Image(systemName: "questionmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.white.opacity(0.10), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 55)
                        .padding(.trailing, 24)
                    }

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 20) {
                    if authMode != nil {
                        loginContent
                    } else {
                        landingContent
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, geometry.safeAreaInsets.bottom + 50)
                .offset(y: keyboardHeight > 0 ? -keyboardHeight * 0.72 : 0)
            }
            .sheet(isPresented: $showInfo) {
                InfoSheet()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                hideKeyboard()
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.9), value: authMode)
            .animation(.spring(response: 0.32, dampingFraction: 0.92), value: keyboardHeight)
            .onReceive(keyboardPublisher) { height in
                keyboardHeight = height
            }
            .fullScreenCover(isPresented: $showSignupFlow) {
                SignupFlowView()
                    .environmentObject(session)
            }
            .fullScreenCover(isPresented: $showForgotPassword) {
                ForgotPasswordView(initialEmail: email)
            }
        }
        .ignoresSafeArea()
    }

    private var landingContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("The home of underground music")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white.opacity(0.8))

            Text("Niche Music")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.white)

            VStack(spacing: 12) {
                Button {
                    showSignupFlow = true
                } label: {
                    Text("Get Started")
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .modifier(GlassButtonModifier())

                Button {
                    authMode = .login
                } label: {
                    HStack(spacing: 4) {
                        Text("Already have an account?")
                            .foregroundColor(.white.opacity(0.75))
                            .font(.system(size: 16, weight: .medium))

                        Text("Log in")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
            .padding(.top, 5)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var loginContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button {
                authMode = nil
                hideKeyboard()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))

                    Text("Welcome back")
                        .font(.system(size: 30, weight: .bold))
                }
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Text("Log in to continue discovering music.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineSpacing(2)

            VStack(spacing: 12) {
                authField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)

                PasswordField(
                    placeholder: "Password",
                    password: $password,
                    textContentType: .password
                )
            }
            .padding(.top, 4)

            if let errorMessage = session.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.red.opacity(0.85))
            }

            Button {
                hideKeyboard()
                Task {
                    await session.signIn(email: email, password: password)
                }
            } label: {
                Text("Log In")
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .modifier(GlassButtonModifier())

            Button {
                hideKeyboard()
                showForgotPassword = true
            } label: {
                Text("Forgot password?")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            Button {
                hideKeyboard()
                authMode = nil
                showSignupFlow = true
            } label: {
                HStack(spacing: 4) {
                    Text("New here?")
                        .foregroundStyle(.white.opacity(0.65))

                    Text("Create account")
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
                .font(.system(size: 15))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func authField(_ placeholder: String, text: Binding<String>, secure: Bool = false) -> some View {
        Group {
            if secure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
            }
        }
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(.white)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .padding()
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var keyboardPublisher: AnyPublisher<CGFloat, Never> {
        Publishers.Merge(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
                .compactMap { notification in
                    notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                }
                .map { $0.height },
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
                .map { _ in CGFloat(0) }
        )
        .eraseToAnyPublisher()
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

struct PasswordField: View {
    let placeholder: String
    @Binding var password: String
    let textContentType: UITextContentType

    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if isVisible {
                    TextField(placeholder, text: $password)
                } else {
                    SecureField(placeholder, text: $password)
                }
            }
            .textContentType(textContentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(.white)
        .padding()
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct GlassButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14))
        } else {
            content
                .background(Color.white.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct InfoSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("What is Niche?")
                .font(.system(size: 32, weight: .bold))

            Text("Niche Music is a music-first social app for discovering underground artists, sharing tracks, following scenes, and supporting artists early.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 16) {
                infoRow("Artist uploads", "Artists can share music directly with listeners.")
                infoRow("Music-first profiles", "Show your taste through tracks, reposts, and artists.")
                infoRow("Spotlights", "Curated features on artists shaping underground music.")
                infoRow("Social discovery", "Find music through people, scenes, and communities.")
            }

            Spacer()
        }
        .padding(24)
    }

    private func infoRow(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))

            Text(subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    LandingPage()
        .environmentObject(SessionStore(bootstrap: false, previewState: .signedOut))
}
