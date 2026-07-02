//
//  EditProfileView.swift
//  Niche Music
//

import PhotosUI
import SwiftUI
import Kingfisher

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var session: SessionStore

    @State private var baseline = EditProfileDraft(
        displayName: "",
        bio: "",
        locationName: "",
        isPrivate: false,
        profileSongId: "",
        profileType: .user,
        allowMessagesFrom: .all,
        allowGroupInvites: true,
        spotifyAccount: "",
        instagramHandle: "",
        tiktokHandle: ""
    )
    @State private var draft = EditProfileDraft(
        displayName: "",
        bio: "",
        locationName: "",
        isPrivate: false,
        profileSongId: "",
        profileType: .user,
        allowMessagesFrom: .all,
        allowGroupInvites: true,
        spotifyAccount: "",
        instagramHandle: "",
        tiktokHandle: ""
    )

    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var pendingAvatarData: Data?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showProfileSongPicker = false
    @State private var profileSongPreview: ProfileSongSelection?

    private var username: String {
        profileStore.me?.username ?? ""
    }

    private var canChangeProfileType: Bool {
        profileStore.me?.canUpdateProfileType ?? false
    }

    private var profileTypeFooter: String {
        if canChangeProfileType {
            return "You can change your profile type once every 14 days."
        }

        if let nextDate = profileStore.me?.nextProfileTypeChangeDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return "You can change your profile type again on \(formatter.string(from: nextDate))."
        }

        return "You can change your profile type once every 14 days."
    }

    private var hasTextChanges: Bool {
        !draft.updateBody(
            comparedTo: baseline,
            requestAvatar: false,
            canChangeProfileType: canChangeProfileType
        ).isEmpty
    }

    private var hasChanges: Bool {
        hasTextChanges || pendingAvatarData != nil
    }

    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()

            if profileStore.me == nil {
                NicheProgress()
            } else {
                editForm
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await save() }
                }
                .fontWeight(.semibold)
                .disabled(!hasChanges || isSaving)
            }
        }
        .overlay {
            if isSaving {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    NicheProgress()
                }
            }
        }
        .onAppear(perform: loadDraft)
        .onChange(of: profileStore.me?.id) { _, _ in
            loadDraft()
        }
        .onChange(of: avatarPickerItem) { _, item in
            Task { await loadPickedAvatar(from: item) }
        }
        .sheet(isPresented: $showProfileSongPicker) {
            ProfileSongPickerView { selection in
                draft.profileSongId = selection.trackId
                profileSongPreview = selection
            }
        }
    }

    private var editForm: some View {
        Form {
            Section {
                avatarSection
            }
            .listRowBackground(Color.white.opacity(0.06))

            Section {
                readOnlyField(title: "Username", value: "@\(username)")

                editField(
                    title: "Display name",
                    text: $draft.displayName,
                    limit: 20
                )

                editField(
                    title: "Bio",
                    text: $draft.bio,
                    limit: 100,
                    axis: .vertical,
                    lineLimit: 3...5
                )

                editField(
                    title: "Location",
                    text: $draft.locationName,
                    limit: 100
                )

                Toggle("Private account", isOn: $draft.isPrivate)
                    .tint(Theme.accentColor)

                Picker("Profile type", selection: $draft.profileType) {
                    ForEach(ProfileType.allCases, id: \.self) { type in
                        Text(type.formattedLabel).tag(type)
                    }
                }
                .disabled(!canChangeProfileType)
                .opacity(canChangeProfileType ? 1 : 0.45)
            } header: {
                Text("Profile")
            } footer: {
                Text(profileTypeFooter)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .listRowBackground(Color.white.opacity(0.06))

            Section {
                profileSongSection
            } header: {
                Text("Profile song")
            } footer: {
                Text("Choose a song to highlight on your profile.")
                    .foregroundStyle(.white.opacity(0.4))
            }
            .listRowBackground(Color.white.opacity(0.06))

            Section("Privacy") {
                Picker("Allow messages from", selection: $draft.allowMessagesFrom) {
                    ForEach(AllowMessagesFrom.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }

                Toggle("Allow group invites", isOn: $draft.allowGroupInvites)
                    .tint(Theme.accentColor)
            }
            .listRowBackground(Color.white.opacity(0.06))

            Section("Links") {
                editField(
                    title: "Spotify",
                    text: $draft.spotifyAccount,
                    placeholder: "Profile link or user id"
                )
                .onChange(of: draft.spotifyAccount) { _, newValue in
                    let normalized = SpotifyAccountFormatting.normalizedAccount(from: newValue)
                    if normalized != newValue {
                        draft.spotifyAccount = normalized
                    }
                }
                editField(
                    title: "Instagram",
                    text: $draft.instagramHandle,
                    placeholder: "Handle"
                )
                editField(
                    title: "TikTok",
                    text: $draft.tiktokHandle,
                    placeholder: "Handle"
                )
            }
            .listRowBackground(Color.white.opacity(0.06))

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.system(size: 14))
                        .foregroundStyle(.red.opacity(0.9))
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            dismissKeyboard()
        }
    }

    private var profileSongSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let preview = profileSongPreview {
                HStack(spacing: 12) {
                    profileSongArtwork(preview.artworkUrl)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(preview.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(preview.artistName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
            } else {
                Text("No profile song selected")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Button {
                showProfileSongPicker = true
            } label: {
                Text(profileSongPreview == nil ? "Choose song" : "Change song")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)
            }
            .buttonStyle(.plain)

            if profileSongPreview != nil || !draft.profileSongId.isEmpty {
                Button("Remove song", role: .destructive) {
                    draft.profileSongId = ""
                    profileSongPreview = nil
                }
                .font(.system(size: 15, weight: .medium))
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func profileSongArtwork(_ artworkUrl: String?) -> some View {
        Group {
            if let artworkUrl,
               let url = URL(string: artworkUrl.replacingOccurrences(of: "{w}x{h}", with: "120x120")) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.08)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.35))
                    }
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var avatarSection: some View {
        HStack(spacing: 16) {
            avatarPreview

            VStack(alignment: .leading, spacing: 8) {
                PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                    Text("Change photo")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accentColor)
                }

                if pendingAvatarData != nil {
                    Text("New photo ready to upload")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var avatarPreview: some View {
        Group {
            if let pendingAvatarData, let uiImage = UIImage(data: pendingAvatarData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if let avatarUrl = profileStore.me?.avatarUrl,
                      let url = URL(string: avatarUrl) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.12)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.4))
                    }
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
    }

    private func loadDraft() {
        guard let user = profileStore.me else { return }
        let initial = EditProfileDraft.from(user: user)
        baseline = initial
        draft = initial

        if let song = user.profileSong {
            profileSongPreview = ProfileSongSelection(
                trackId: song.id,
                name: song.name,
                artistName: song.artist.name,
                artworkUrl: song.artworkUrl
            )
        } else {
            profileSongPreview = nil
        }
    }

    private func loadPickedAvatar(from item: PhotosPickerItem?) async {
        guard let item else {
            pendingAvatarData = nil
            return
        }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.85) else {
            errorMessage = "Couldn't use that photo."
            return
        }

        pendingAvatarData = jpeg
        errorMessage = nil
    }

    private func save() async {
        guard hasChanges else { return }

        isSaving = true
        errorMessage = nil

        do {
            try await profileStore.updateProfile(
                draft: draft,
                baseline: baseline,
                avatarJPEGData: pendingAvatarData
            )

            if let avatarUrl = profileStore.me?.avatarUrl {
                session.updateAvatarUrl(avatarUrl)
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }

    @ViewBuilder
    private func readOnlyField(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    @ViewBuilder
    private func editField(
        title: String,
        text: Binding<String>,
        limit: Int? = nil,
        placeholder: String = "",
        axis: Axis = .horizontal,
        lineLimit: ClosedRange<Int>? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                if let limit {
                    Text("\(text.wrappedValue.count)/\(limit)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            if let lineLimit {
                TextField(placeholder, text: text, axis: axis)
                    .lineLimit(lineLimit)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .onChange(of: text.wrappedValue) { _, newValue in
                        guard let limit, newValue.count > limit else { return }
                        text.wrappedValue = String(newValue.prefix(limit))
                    }
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .onChange(of: text.wrappedValue) { _, newValue in
                        guard let limit, newValue.count > limit else { return }
                        text.wrappedValue = String(newValue.prefix(limit))
                    }
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        EditProfileView()
            .environmentObject(ProfileStore.preview)
            .environmentObject(
                SessionStore(
                    bootstrap: false,
                    previewState: .signedIn(.preview)
                )
            )
    }
}
#endif
