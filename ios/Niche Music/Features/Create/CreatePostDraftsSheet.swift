//
//  CreatePostDraftsSheet.swift
//  Niche Music
//

import SwiftUI

struct CreatePostDraftsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var draftStore: PostDraftStore
    let onSelect: (PostDraftRecord) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if draftStore.drafts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 34))
                            .foregroundStyle(.white.opacity(0.28))
                        Text("No drafts yet")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                        Text("Drafts save locally on your device while you compose.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.38))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(draftStore.drafts) { draft in
                            Button {
                                onSelect(draft)
                                dismiss()
                            } label: {
                                draftRow(draft)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                draftStore.deleteDraft(id: draftStore.drafts[index].id)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.backgroundColor.ignoresSafeArea())
            .navigationTitle("Drafts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
        }
    }

    private func draftRow(_ draft: PostDraftRecord) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(width: 54, height: 54)
                .overlay {
                    Image(systemName: draft.postType.icon)
                        .foregroundStyle(.white.opacity(0.45))
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(draft.previewLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)

                Text("\(draft.postType.title) · \(draft.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
