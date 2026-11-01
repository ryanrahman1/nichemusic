//
//  PostDraftStore.swift
//  Niche Music
//

import Foundation
import Combine

@MainActor
final class PostDraftStore: ObservableObject {
    @Published private(set) var drafts: [PostDraftRecord] = []

    private let fileManager = FileManager.default

    private var draftsDirectory: URL {
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("PostDrafts", isDirectory: true)
    }

    init() {
        loadDrafts()
    }

    func loadDrafts() {
        ensureDirectory()

        guard let urls = try? fileManager.contentsOfDirectory(
            at: draftsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            drafts = []
            return
        }

        drafts = urls.compactMap { url -> PostDraftRecord? in
            let jsonURL = url.appendingPathComponent("draft.json")
            guard let data = try? Data(contentsOf: jsonURL) else { return nil }
            return try? JSONDecoder().decode(PostDraftRecord.self, from: data)
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    func saveDraft(
        id: String?,
        postId: String,
        postType: CreatePostType,
        captureMode: CreatePostCaptureMode,
        caption: String,
        visibility: PostVisibility,
        music: CreatePostMusicSelection?,
        media: CreatePostLocalMedia?
    ) throws -> PostDraftRecord {
        ensureDirectory()

        let draftId = id ?? UUID().uuidString
        let folder = draftsDirectory.appendingPathComponent(draftId, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        var mediaFileName: String?
        var mediaKind: CreatePostLocalMedia.Kind?
        var mediaWidth: Int?
        var mediaHeight: Int?
        var mediaDurationMs: Int?

        if let media {
            let ext = media.kind == .video ? "mp4" : "jpg"
            mediaFileName = "media.\(ext)"
            mediaKind = media.kind
            mediaWidth = media.width
            mediaHeight = media.height
            mediaDurationMs = media.durationMs

            let destination = folder.appendingPathComponent(mediaFileName!)
            if media.fileURL != destination {
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: media.fileURL, to: destination)
            }
        } else {
            let existingMedia = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            existingMedia?
                .filter { $0.lastPathComponent.hasPrefix("media.") }
                .forEach { try? fileManager.removeItem(at: $0) }
        }

        let record = PostDraftRecord(
            id: draftId,
            postId: postId,
            postType: postType,
            captureMode: captureMode,
            caption: caption,
            visibility: visibility,
            music: music,
            mediaFileName: mediaFileName,
            mediaKind: mediaKind,
            mediaWidth: mediaWidth,
            mediaHeight: mediaHeight,
            mediaDurationMs: mediaDurationMs,
            updatedAt: Date()
        )

        let data = try JSONEncoder().encode(record)
        try data.write(to: folder.appendingPathComponent("draft.json"), options: .atomic)

        loadDrafts()
        return record
    }

    func mediaURL(for draft: PostDraftRecord) -> URL? {
        guard let mediaFileName = draft.mediaFileName else { return nil }
        let url = draftsDirectory
            .appendingPathComponent(draft.id, isDirectory: true)
            .appendingPathComponent(mediaFileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func loadMedia(for draft: PostDraftRecord) -> CreatePostLocalMedia? {
        guard
            let url = mediaURL(for: draft),
            let kind = draft.mediaKind,
            let width = draft.mediaWidth,
            let height = draft.mediaHeight
        else {
            return nil
        }

        return CreatePostLocalMedia(
            kind: kind,
            fileURL: url,
            width: width,
            height: height,
            durationMs: draft.mediaDurationMs
        )
    }

    func deleteDraft(id: String) {
        let folder = draftsDirectory.appendingPathComponent(id, isDirectory: true)
        try? fileManager.removeItem(at: folder)
        drafts.removeAll { $0.id == id }
    }

    private func ensureDirectory() {
        if !fileManager.fileExists(atPath: draftsDirectory.path) {
            try? fileManager.createDirectory(at: draftsDirectory, withIntermediateDirectories: true)
        }
    }
}
