//
//  SettingsView.swift
//  Niche Music
//
//  Created by Ryan Rahman on 5/24/26.
//

import SwiftUI

enum SettingsDestination: Hashable {
    case feedback
    case report
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var showLogoutConfirm = false
    @State private var showDeletedAlert = false
    @State private var path = NavigationPath()
    @EnvironmentObject var session: SessionStore
    
    @EnvironmentObject var profileStore: ProfileStore

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                List {
                    Section {
                        settingsRow(icon: "envelope", label: "Send Feedback") {
                            path.append(SettingsDestination.feedback)
                        }
                        settingsRow(icon: "exclamationmark.bubble", label: "Report an Issue") {
                            path.append(SettingsDestination.report)
                        }
                    }

                    Section {
                        settingsRow(icon: "rectangle.portrait.and.arrow.right", label: "Log Out") {
                            showLogoutConfirm = true
                        }
                        settingsRow(icon: "trash", label: "Delete Account", destructive: true) {
                            showDeleteConfirm = true
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 4) {
                        Text("©2026 Niche Music, LLC")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.25))
                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0")")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.2))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .feedback:
                    FeedbackFormView(
                        title: "Send Feedback",
                        placeholder: "What's on your mind?",
                        buttonLabel: "Send Feedback"
                    ) { text in
                        let userId = session.currentUser?.id ?? "app"
                        try await ReportsService.submit(
                            targetType: .other,
                            targetId: userId,
                            message: text,
                            content: ["kind": "feedback", "source": "settings"]
                        )
                    }
                case .report:
                    FeedbackFormView(
                        title: "Report an Issue",
                        placeholder: "Describe the issue...",
                        buttonLabel: "Submit Report"
                    ) { text in
                        let userId = session.currentUser?.id ?? "app"
                        try await ReportsService.submit(
                            targetType: .other,
                            targetId: userId,
                            message: text,
                            content: ["kind": "issue", "source": "settings"]
                        )
                    }
                }
            }
            .alert("Log Out", isPresented: $showLogoutConfirm) {
                Button("Log Out", role: .destructive) {
                    Task {
                        await session.signOut()
                        profileStore.reset()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to log out?")
            }
            .alert("Delete Account", isPresented: $showDeleteConfirm) {
                Button("Delete Account", role: .destructive) {
                    Task { try await APIClient.shared.requestVoid(Endpoints.deleteAccount, method: .post) }
                    showDeletedAlert = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account and all your data, within 7 days. This can't be undone.")
            }
            .alert("Account Deleted", isPresented: $showDeletedAlert) {
                Button("Sign out") {
                    Task { await session.signOut() }
                }
            } message: {
                    Text("Your account has been deleted. We're sorry to see you go. Click sign out to log out and return to the login screen.")
                }
        }
    }

    @ViewBuilder
    private func settingsRow(
        icon: String,
        label: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .frame(width: 22)
                    .foregroundStyle(destructive ? .red : .white.opacity(0.7))
                Text(label)
                    .font(.system(size: 16))
                    .foregroundStyle(destructive ? .red : .white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
        .listRowBackground(Color.white.opacity(0.06))
    }
}

struct FeedbackFormView: View {
    let title: String
    let placeholder: String
    let buttonLabel: String
    let onSubmit: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isSubmitting = false
    @State private var submitted = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.06))

                    if text.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.white.opacity(0.3))
                            .font(.system(size: 15))
                            .padding(14)
                    }

                    TextEditor(text: $text)
                        .scrollContentBackground(.hidden)
                        .background(.clear)
                        .foregroundStyle(.white)
                        .font(.system(size: 15))
                        .padding(10)
                        .focused($focused)
                }
                .frame(minHeight: 140, maxHeight: 200)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.red.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    Task { await submit() }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white)

                        if isSubmitting {
                            NicheProgress()
                        } else if submitted {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.black)
                                .font(.system(size: 15, weight: .semibold))
                        } else {
                            Text(buttonLabel)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.black)
                        }
                    }
                    .frame(height: 52)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                .animation(.easeInOut(duration: 0.15), value: text.isEmpty)

                Spacer()
            }
            .padding(20)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { focused = true }
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil

        do {
            try await onSubmit(text)
            submitted = true
            try? await Task.sleep(nanoseconds: 600_000_000)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            submitted = false
        }

        isSubmitting = false
    }
}
