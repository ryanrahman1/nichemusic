//
//  ProfileConnectionsListView.swift
//  Niche Music
//

import SwiftUI
import Kingfisher

struct ProfileConnectionsListView: View {
    @StateObject private var store: ProfileConnectionsStore

    init(kind: ProfileConnectionsKind, username: String? = nil) {
        _store = StateObject(
            wrappedValue: ProfileConnectionsStore(kind: kind, username: username)
        )
    }

    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()

            if store.isLoading && store.users.isEmpty {
                NicheProgress()
            } else {
                connectionsForm
            }
        }
        .navigationTitle(store.kind.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await store.load()
        }
        .refreshable {
            await store.load()
        }
    }

    @ViewBuilder
    private var connectionsForm: some View {
        Form {
            if let error = store.errorMessage, store.users.isEmpty {
                Section {
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundStyle(.red.opacity(0.9))
                    Button("Try again") {
                        Task { await store.load() }
                    }
                    .foregroundStyle(Theme.accentColor)
                }
                .listRowBackground(Color.white.opacity(0.06))
            } else if store.users.isEmpty {
                Section {
                    Text(store.kind.emptyTitle)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .listRowBackground(Color.white.opacity(0.06))
            } else {
                Section {
                    ForEach(store.users) { user in
                        connectionRow(user)
                    }
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    private func connectionRow(_ user: FollowListProfile) -> some View {
        NavigationLink {
            OtherProfileView(username: user.username)
        } label: {
            HStack(spacing: 14) {
                avatar(for: user)
                    .frame(width: 44, height: 44)

                Text("@\(user.username)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func avatar(for user: FollowListProfile) -> some View {
        if let avatarUrl = user.avatarUrl,
           let url = URL(string: avatarUrl) {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            Circle()
                .fill(.white.opacity(0.12))
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.45))
                }
        }
    }
}

#if DEBUG
#Preview("Followers") {
    NavigationStack {
        ProfileConnectionsListView(kind: .followers)
    }
}
#endif
