//
//  CreatePostStore.swift
//  Niche Music
//

import Foundation
import Combine
import UIKit

@MainActor
final class CreatePostStore: ObservableObject {
    @Published var postType: CreatePostType = .image
    @Published var captureMode: CreatePostCaptureMode = .photo
    @Published var caption = ""
    @Published var visibility: PostVisibility = .public
    @Published var music: CreatePostMusicSelection?
    @Published var media: CreatePostLocalMedia?
    @Published private(set) var postId: String = CreatePostID.makePostId()
    @Published private(set) var activeDraftId: String?
    @Published private(set) var publishStage: CreatePostPublishStage = .idle
    @Published private(set) var uploadProgress: Double = 0

    private let api = APIClient.shared
    private var publishGeneration = 0

    var canContinueToCompose: Bool {
        switch postType {
        case .image, .video:
            return media != nil
        case .pmo:
            return true
        }
    }

    var canPublish: Bool {
        switch postType {
        case .image, .video:
            return media != nil
        case .pmo:
            guard music != nil else { return false }
            let prompt = pmoPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            return !prompt.isEmpty
        }
    }

    var pmoPrompt: String {
        get {
            let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            return music.map { "Put me on to songs like \($0.title)" } ?? ""
        }
        set {
            caption = newValue
        }
    }

    func resetForNewPost() {
        publishGeneration += 1
        postType = .image
        captureMode = .photo
        caption = ""
        visibility = .public
        music = nil
        media = nil
        postId = CreatePostID.makePostId()
        activeDraftId = nil
        publishStage = .idle
        uploadProgress = 0
    }

    func applyDraft(_ draft: PostDraftRecord, mediaURL: CreatePostLocalMedia?) {
        if draft.postType == .image && draft.captureMode == .video {
            postType = .video
        } else {
            postType = draft.postType
        }
        captureMode = postType == .video ? .video : .photo
        caption = draft.caption
        visibility = draft.visibility
        music = draft.music
        media = mediaURL
        postId = draft.postId
        activeDraftId = draft.id
        publishStage = .idle
        uploadProgress = 0
    }

    func setPostType(_ type: CreatePostType) {
        postType = type

        switch type {
        case .image:
            captureMode = .photo
            if let music, music.source == .catalog {
                self.music = nil
            }
        case .video:
            captureMode = .video
            if let music, music.source == .catalog {
                self.music = nil
            }
        case .pmo:
            captureMode = .photo
            media = nil
        }
    }

    func setCapturedImage(_ image: UIImage) async {
        let url = CreatePostMediaSupport.temporaryMediaURL(kind: .image)
        do {
            try CreatePostMediaSupport.writeJPEG(image, to: url)
            let dims = CreatePostMediaSupport.dimensions(for: image)
            media = CreatePostLocalMedia(
                kind: .image,
                fileURL: url,
                width: dims.width,
                height: dims.height,
                durationMs: nil
            )
            captureMode = .photo
        } catch {
            publishStage = .failed(error.localizedDescription)
        }
    }

    func setCapturedVideo(from sourceURL: URL) async {
        let destination = CreatePostMediaSupport.temporaryMediaURL(kind: .video)
        do {
            try CreatePostMediaSupport.copyVideo(from: sourceURL, to: destination)
            guard let metadata = await CreatePostMediaSupport.videoMetadata(for: destination) else {
                throw CreatePostStoreError.invalidState
            }
            media = CreatePostLocalMedia(
                kind: .video,
                fileURL: destination,
                width: metadata.width,
                height: metadata.height,
                durationMs: metadata.durationMs
            )
            captureMode = .video
        } catch {
            publishStage = .failed(error.localizedDescription)
        }
    }

    func clearMedia() {
        media = nil
    }

    func saveDraft(using draftStore: PostDraftStore) throws -> PostDraftRecord {
        try draftStore.saveDraft(
            id: activeDraftId,
            postId: postId,
            postType: postType,
            captureMode: captureMode,
            caption: caption,
            visibility: visibility,
            music: music,
            media: media
        )
    }

    func cancelPublish() {
        publishGeneration += 1
        publishStage = .idle
        uploadProgress = 0
    }

    func publish(draftStore: PostDraftStore, postsStore: PostsStore) async -> String? {
        guard canPublish else { return nil }

        publishGeneration += 1
        let generation = publishGeneration

        publishStage = .preparing
        uploadProgress = 0.05

        do {
            let resolvedKind = resolvedAPIKind()
            var uploadedMedia: [CreatePostMediaInput] = []

            if let media, postType != .pmo {
                publishStage = .uploadingMedia
                uploadProgress = 0.15
                let uploaded = try await uploadMedia(media, generation: generation)
                guard generation == publishGeneration else { throw CreatePostStoreError.cancelled }
                uploadedMedia = [uploaded]
                uploadProgress = 0.72
            }

            publishStage = .creatingPost
            uploadProgress = 0.82

            let body = try await buildCreateBody(kind: resolvedKind, media: uploadedMedia, generation: generation)
            guard generation == publishGeneration else { throw CreatePostStoreError.cancelled }

            let response: CreatePostResultResponse = try await api.request(
                Endpoints.createPost,
                method: .post,
                body: body,
                preserveBodyKeyNames: true
            )

            guard generation == publishGeneration else { throw CreatePostStoreError.cancelled }

            publishStage = .finishing
            uploadProgress = 0.92

            await postsStore.loadPost(id: response.post.id, force: true)

            if let activeDraftId {
                draftStore.deleteDraft(id: activeDraftId)
                self.activeDraftId = nil
            }

            uploadProgress = 1
            publishStage = .completed(postId: response.post.id)
            return response.post.id
        } catch {
            if generation != publishGeneration {
                return nil
            }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            publishStage = .failed(message)
            return nil
        }
    }

    func searchNicheTracks(query: String) async throws -> [NicheTrackSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let response: NicheTrackSearchResponse = try await api.request(
            Endpoints.nicheTrackSearch,
            method: .get,
            query: ["q": trimmed, "limit": "20"]
        )
        return response.tracks
    }

    func searchCatalogSongs(query: String) async throws -> [AppleMusicSearchSong] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let response: AppleMusicSearchResponse = try await api.request(
            Endpoints.appleMusicSearch,
            method: .get,
            query: ["q": trimmed, "types": "songs"]
        )
        return response.data.results?.songs?.data ?? []
    }

    func resolveCatalogTrack(appleSourceId: String) async throws -> String {
        let response: AppleSongIdLookupResponse = try await api.request(
            Endpoints.appleMusicSong(id: appleSourceId),
            method: .get
        )
        return response.track.id
    }

    private func resolvedAPIKind() -> PostKind {
        switch postType {
        case .image:
            return .image
        case .video:
            return .video
        case .pmo:
            return .pmo
        }
    }

    private func uploadMedia(_ media: CreatePostLocalMedia, generation: Int) async throws -> CreatePostMediaInput {
        let format = media.kind == .video ? "mp4" : "jpeg"
        let presign: PostMediaPresignResponse = try await api.request(
            Endpoints.presignPostMedia,
            method: .post,
            body: PostMediaPresignBody(postId: postId, mediaKind: media.kind.rawValue, format: format),
            preserveBodyKeyNames: true
        )

        guard generation == publishGeneration else { throw CreatePostStoreError.cancelled }

        postId = presign.postId

        let payload = try Data(contentsOf: media.fileURL)
        guard payload.count <= presign.upload.maxBytes else {
            throw CreatePostStoreError.mediaTooLarge
        }

        guard let uploadURL = URL(string: presign.upload.uploadUrl) else {
            throw CreatePostStoreError.uploadFailed
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue(presign.upload.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = payload

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CreatePostStoreError.uploadFailed
        }

        uploadProgress = 0.68

        return CreatePostMediaInput(
            kind: media.kind.rawValue,
            objectKey: presign.upload.objectKey,
            width: media.width,
            height: media.height,
            durationMs: media.kind == .video ? media.durationMs : nil
        )
    }

    private func buildCreateBody(
        kind: PostKind,
        media: [CreatePostMediaInput],
        generation: Int
    ) async throws -> CreatePostBody {
        guard generation == publishGeneration else { throw CreatePostStoreError.cancelled }

        var trackId: String?
        var nicheTrackId: String?

        if let music {
            switch music.source {
            case .niche:
                nicheTrackId = music.nicheTrackId
            case .catalog:
                if let existing = music.catalogTrackId {
                    trackId = existing
                } else if let appleSourceId = music.appleSourceId {
                    trackId = try await resolveCatalogTrack(appleSourceId: appleSourceId)
                }
            }
        }

        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let template: CreatePostTemplateBody?
        if kind == .pmo {
            template = CreatePostTemplateBody(
                name: "pmo",
                data: CreatePostTemplateDataBody(
                    prompt: pmoPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
                    allowTrackReplies: true
                )
            )
        } else {
            template = nil
        }

        return CreatePostBody(
            postId: postId,
            kind: kind.rawValue,
            visibility: visibility.rawValue,
            trackId: trackId,
            nicheTrackId: nicheTrackId,
            content: CreatePostContentBody(
                version: 1,
                kind: kind.rawValue,
                caption: trimmedCaption,
                media: media,
                template: template,
                metadata: ["source": "ios_create_v1"]
            )
        )
    }
}
