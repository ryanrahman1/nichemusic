//
//  EditPostView.swift
//  Niche Music
//

import SwiftUI

struct EditPostView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var postsStore: PostsStore

    let post: Post

    @State private var caption: String
    @State private var visibility: PostVisibility
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(post: Post) {
        self.post = post
        _caption = State(initialValue: post.content.caption ?? "")
        _visibility = State(initialValue: post.visibility)
    }

    private var hasChanges: Bool {
        caption.trimmingCharacters(in: .whitespacesAndNewlines)
            != (post.content.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            || visibility != post.visibility
    }

    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()

            Form {
                Section {
                    TextField("Caption", text: $caption, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Caption")
                }

                Section {
                    Picker("Visibility", selection: $visibility) {
                        Text("Public").tag(PostVisibility.public)
                        Text("Private").tag(PostVisibility.private)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Who can see this")
                } footer: {
                    Text("Private posts are only visible to you.")
                }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Edit Post")
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
        .alert("Couldn't save post", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        var body = UpdatePostBody(
            visibility: visibility != post.visibility ? visibility : nil,
            content: nil
        )

        if trimmedCaption != (post.content.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines) {
            body.content = UpdatePostContentBody(caption: trimmedCaption)
        }

        do {
            _ = try await postsStore.updatePost(id: post.id, body: body)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
