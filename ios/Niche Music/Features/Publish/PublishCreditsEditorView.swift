//
//  PublishCreditsEditorView.swift
//  Niche Music
//

import Kingfisher
import SwiftUI

struct PublishCreditsEditorView: View {
    @Binding var credits: [PublishCreditEntry]
    let onSave: ([PublishCreditEntry]) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var searchStore = DiscoverSearchStore()
    @State private var query = ""
    @State private var draftCredits: [PublishCreditEntry] = []

    var body: some View {
        Form {
            Section {
                ForEach($draftCredits) { $credit in
                    HStack(spacing: 12) {
                        creditAvatar(credit)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(credit.displayName ?? credit.username)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("@\(credit.username)")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.45))
                        }

                        Spacer()

                        Toggle("Primary", isOn: $credit.isPrimary)
                            .labelsHidden()
                            .tint(Theme.accentColor)
                    }
                }
                .onDelete(perform: deleteCredits)
            } header: {
                Text("Credits")
            } footer: {
                Text("Send the full credited artist list when saving.")
                    .foregroundStyle(.white.opacity(0.4))
            }
            .listRowBackground(Color.white.opacity(0.06))

            Section("Add artist") {
                TextField("Search profiles", text: $query)
                    .foregroundStyle(.white)
                    .onChange(of: query) { _, value in
                        searchStore.updateQuery(value)
                    }

                if searchStore.isLoadingResults {
                    ProgressView().tint(.white)
                }

                ForEach(searchStore.results?.profiles ?? []) { profile in
                    Button {
                        addProfile(profile)
                    } label: {
                        HStack(spacing: 12) {
                            if let avatarUrl = profile.avatarUrl, let url = URL(string: avatarUrl) {
                                KFImage(url)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 36, height: 36)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Color.white.opacity(0.12))
                                    .frame(width: 36, height: 36)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName ?? profile.username)
                                    .foregroundStyle(.white)
                                Text("@\(profile.username)")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.45))
                            }

                            Spacer()

                            if draftCredits.contains(where: { $0.artistId == profile.id }) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(Color.white.opacity(0.06))
        }
        .publishFormStyle()
        .navigationTitle("Credits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    credits = draftCredits
                    onSave(draftCredits)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            if draftCredits.isEmpty {
                draftCredits = credits
            }
        }
        .onChange(of: credits) { _, value in
            draftCredits = value
        }
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 else { return }
            await searchStore.loadResults(query: trimmed)
        }
    }

    @ViewBuilder
    private func creditAvatar(_ credit: PublishCreditEntry) -> some View {
        if let avatarUrl = credit.avatarUrl, let url = URL(string: avatarUrl) {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 40, height: 40)
        }
    }

    private func addProfile(_ profile: GlobalSearchProfileResult) {
        guard !draftCredits.contains(where: { $0.artistId == profile.id }) else { return }
        draftCredits.append(.from(profile))
        PublishHaptics.tap()
    }

    private func deleteCredits(at offsets: IndexSet) {
        draftCredits.remove(atOffsets: offsets)
        PublishHaptics.selection()
    }
}
