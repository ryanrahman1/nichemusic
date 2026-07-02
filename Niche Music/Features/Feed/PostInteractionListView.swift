//
//  PostInteractionListView.swift
//  Niche Music
//

import SwiftUI
import Kingfisher

struct PostInteractionListView: View {
    @StateObject private var store: PostInteractionListStore
    @Environment(\.dismiss) private var dismiss

    init(postId: String, kind: PostInteractionKind) {
        _store = StateObject(wrappedValue: PostInteractionListStore(postId: postId, kind: kind))
    }

    var body: some View {
        NavigationStack {
            listContent
        }
    }

    private var listContent: some View {
        List {
            if store.isLoading && store.users.isEmpty {
                loadingRow
            } else if let error = store.errorMessage, store.users.isEmpty {
                errorRow(error)
            } else if store.users.isEmpty {
                emptyRow
            } else {
                ForEach(store.users) { user in
                    userRow(user)
                        .onAppear {
                            Task { await store.loadMoreIfNeeded(currentUser: user) }
                        }
                }

                if store.isLoadingMore {
                    loadingMoreRow
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(store.kind.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done", systemImage: "xmark") {
                    dismiss()
                }
            }
        }
        .task {
            await store.loadInitial()
        }
    }

    private var loadingRow: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .listRowSeparator(.hidden)
    }

    private var loadingMoreRow: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .listRowSeparator(.hidden)
    }

    private func errorRow(_ error: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't Load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
        } actions: {
            Button("Try Again") {
                Task { await store.loadInitial() }
            }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var emptyRow: some View {
        ContentUnavailableView(
            store.kind == .likes ? "No Likes Yet" : "No Reposts Yet",
            systemImage: store.kind == .likes ? "heart" : "arrow.2.squarepath",
            description: Text("Be the first to interact with this post.")
        )
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func userRow(_ user: PostInteractionUser) -> some View {
        ProfileUsernameLink(username: user.username) {
            HStack(spacing: 12) {
                avatar(for: user)
                    .frame(width: 50, height: 50)

                Text("@\(user.username)")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
    }

    @ViewBuilder
    private func avatar(for user: PostInteractionUser) -> some View {
        if let avatarUrl = user.avatarUrl,
           let url = URL(string: avatarUrl) {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color(.tertiarySystemFill))
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(.secondaryLabel))
                }
        }
    }
}
