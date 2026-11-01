//
//  PublishMusicStore.swift
//  Niche Music
//

import Foundation
import Combine

@MainActor
final class PublishMusicStore: ObservableObject {
    enum Flow {
        case choosingType
        case single(PublishTrackDraft)
        case release(PublishReleaseDraft)
        case reviewSingle(PublishTrackDraft)
        case reviewRelease(PublishReleaseDraft)
    }

    @Published var flow: Flow = .choosingType
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var publishProgress: Double = 0
    @Published private(set) var didPublish = false
    @Published private(set) var singleDraftSummaries: [PublishTrackDraftSummary] = []
    @Published private(set) var releaseDraftSummaries: [PublishReleaseDraftSummary] = []
    @Published private(set) var isLoadingDrafts = false

    let uploadToasts = PublishUploadToastCenter()

    private let api = APIClient.shared
    private var metadataSyncTasks: [String: Task<Void, Never>] = [:]

    private func postPublish<T: Decodable>(_ endpoint: APIEndpoint, body: Encodable) async throws -> T {
        try await api.request(
            endpoint,
            method: .post,
            body: body,
            preserveBodyKeyNames: true
        )
    }

    func reset() {
        metadataSyncTasks.values.forEach { $0.cancel() }
        metadataSyncTasks.removeAll()
        flow = .choosingType
        isBusy = false
        errorMessage = nil
        publishProgress = 0
        didPublish = false
        singleDraftSummaries = []
        releaseDraftSummaries = []
        isLoadingDrafts = false
    }

    // MARK: - Saved drafts

    func refreshSavedDrafts() async {
        isLoadingDrafts = true
        defer { isLoadingDrafts = false }

        do {
            async let singles: PublishTrackDraftListResponse = api.request(
                Endpoints.listNicheTrackDrafts,
                method: .get
            )
            async let releases: PublishReleaseDraftListResponse = api.request(
                Endpoints.listNicheReleaseDrafts,
                method: .get
            )

            let loadedSingles = try await singles
            let loadedReleases = try await releases
            singleDraftSummaries = loadedSingles.drafts
            releaseDraftSummaries = loadedReleases.drafts
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resumeSingleDraft(id: String) async {
        isBusy = true
        errorMessage = nil

        do {
            let response: PublishSingleDraftDetailResponse = try await api.request(
                Endpoints.nicheTrackDraft(id: id),
                method: .get
            )
            let draft = PublishDraftMapping.trackDraft(
                from: response.draft,
                uploadStatus: response.uploadStatus
            )
            flow = .single(draft)
            isBusy = false
        } catch {
            errorMessage = error.localizedDescription
            isBusy = false
            PublishHaptics.error()
        }
    }

    func resumeReleaseDraft(id: String) async {
        isBusy = true
        errorMessage = nil

        do {
            let response: PublishReleaseDraftDetailResponse = try await api.request(
                Endpoints.nicheReleaseDraft(releaseDraftId: id),
                method: .get
            )
            guard let draft = PublishDraftMapping.releaseDraft(from: response) else {
                throw PublishMusicError.draftNotCreated
            }
            flow = .release(draft)
            isBusy = false
        } catch {
            errorMessage = error.localizedDescription
            isBusy = false
            PublishHaptics.error()
        }
    }

    func deleteSingleDraft(id: String) async -> Bool {
        do {
            try await api.requestVoid(
                Endpoints.deleteNicheTrackDraft(id: id),
                method: .post
            )
            singleDraftSummaries.removeAll { $0.id == id }
            PublishHaptics.success()
            return true
        } catch {
            errorMessage = error.localizedDescription
            PublishHaptics.error()
            return false
        }
    }

    func deleteReleaseDraft(id: String) async -> Bool {
        do {
            try await api.requestVoid(
                Endpoints.deleteNicheReleaseDraft(releaseDraftId: id),
                method: .post
            )
            releaseDraftSummaries.removeAll { $0.id == id }
            PublishHaptics.success()
            return true
        } catch {
            errorMessage = error.localizedDescription
            PublishHaptics.error()
            return false
        }
    }

    func replaceSingleDraftAudio(with audioURL: URL) async {
        guard case .single(let draft) = flow else { return }

        isBusy = true
        errorMessage = nil

        do {
            guard let format = PublishMediaSupport.musicFormat(for: audioURL) else {
                throw PublishMusicError.unsupportedAudioFormat
            }

            let copied = try PublishMediaSupport.copiedFileURL(
                from: audioURL,
                prefix: "publish-audio",
                ext: format
            )
            let durationMs = await PublishMediaSupport.audioDurationMs(for: copied)

            let response: CreateTrackDraftResponse = try await postPublish(
                Endpoints.reuploadNicheTrackDraftMusic(id: draft.id),
                body: CreateTrackDraftBody(musicFormat: format)
            )

            updateSingleTrack { track in
                track.localAudioURL = copied
                track.audioFileLabel = audioURL.lastPathComponent
                track.durationMs = durationMs
                track.audioUpload = .uploading
            }
            isBusy = false

            startAudioUpload(
                trackId: draft.id,
                fileURL: copied,
                upload: response.upload,
                releaseDraftId: nil
            ) { [weak self] state in
                self?.updateSingleTrack { $0.audioUpload = state }
            }
        } catch {
            errorMessage = error.localizedDescription
            isBusy = false
            PublishHaptics.error()
        }
    }

    // MARK: - Single flow

    func beginSingle(with audioURL: URL) async {
        isBusy = true
        errorMessage = nil

        do {
            guard let format = PublishMediaSupport.musicFormat(for: audioURL) else {
                throw PublishMusicError.unsupportedAudioFormat
            }

            let copied = try PublishMediaSupport.copiedFileURL(
                from: audioURL,
                prefix: "publish-audio",
                ext: format
            )
            let durationMs = await PublishMediaSupport.audioDurationMs(for: copied)

            let response: CreateTrackDraftResponse = try await postPublish(
                Endpoints.createNicheTrackDraft,
                body: CreateTrackDraftBody(musicFormat: format)
            )

            var draft = PublishTrackDraft(
                id: response.id,
                localAudioURL: copied,
                audioFileLabel: audioURL.lastPathComponent,
                durationMs: durationMs
            )

            flow = .single(draft)
            isBusy = false

            startAudioUpload(
                trackId: draft.id,
                fileURL: copied,
                upload: response.upload,
                releaseDraftId: nil
            ) { [weak self] state in
                self?.updateSingleTrack { $0.audioUpload = state }
            }

            scheduleSingleMetadataSync()
        } catch {
            errorMessage = error.localizedDescription
            isBusy = false
            PublishHaptics.error()
        }
    }

    func updateSingleTrack(_ mutate: (inout PublishTrackDraft) -> Void) {
        guard case .single(var draft) = flow else { return }
        mutate(&draft)
        flow = .single(draft)
    }

    func scheduleSingleMetadataSync() {
        guard case .single(let draft) = flow else { return }
        scheduleMetadataSync(key: "single-\(draft.id)") { [weak self] in
            await self?.syncSingleMetadata()
        }
    }

    func syncSingleMetadata(includeCredits: Bool = false) async {
        guard case .single(let draft) = flow else { return }

        var body = UpdateTrackDraftBody(
            name: trimmedOrNil(draft.name),
            releaseDate: PublishDateFormatting.apiString(from: draft.releaseDate),
            explicit: draft.explicit,
            durationMs: draft.durationMs,
            bpm: draft.bpmValue,
            visibility: draft.visibility.rawValue
        )

        if includeCredits {
            body.credits = creditsBody(from: draft.credits)
        }

        do {
            let response: UpdateTrackDraftResponse = try await postPublish(
                Endpoints.updateNicheTrackDraft(id: draft.id),
                body: body
            )

            if let artworkURL = response.draft?.artworkUrl {
                updateSingleTrack { $0.artworkURL = artworkURL }
            }
            if let momentURL = response.draft?.momentUrl {
                updateSingleTrack { track in
                    if track.momentUpload.isUploaded || track.momentUpload.isUploading {
                        // keep local upload state
                    }
                    _ = momentURL
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func uploadSingleArtwork(jpegData: Data) async {
        guard case .single(let draft) = flow else { return }

        updateSingleTrack {
            $0.pendingArtworkJPEG = jpegData
            $0.hasCustomArtwork = true
            $0.artworkUpload = .uploading
        }

        let toastID = uploadToasts.begin("Uploading artwork")

        do {
            let response: UpdateTrackDraftResponse = try await postPublish(
                Endpoints.updateNicheTrackDraft(id: draft.id),
                body: UpdateTrackDraftBody(
                    image: PublishImageUploadBody(hasImage: true, imageFormat: "jpeg")
                )
            )

            guard let upload = response.upload?.image else {
                throw PublishMusicError.uploadFailed
            }

            try await putFile(data: jpegData, upload: upload)

            updateSingleTrack {
                $0.artworkURL = upload.publicUrl
                $0.artworkUpload = .uploaded
            }
            uploadToasts.complete(toastID)
            await syncSingleMetadata()
        } catch {
            updateSingleTrack { $0.artworkUpload = .failed(error.localizedDescription) }
            uploadToasts.fail(toastID)
            errorMessage = error.localizedDescription
        }
    }

    func uploadSingleMoment(from url: URL) async {
        guard case .single(let draft) = flow else { return }
        guard let format = PublishMediaSupport.videoFormat(for: url) else {
            errorMessage = PublishMusicError.unsupportedVideoFormat.localizedDescription
            return
        }

        updateSingleTrack {
            $0.pendingMomentURL = url
            $0.momentUpload = .uploading
        }

        let toastID = uploadToasts.begin("Uploading moment")

        do {
            let copied = try PublishMediaSupport.copiedFileURL(from: url, prefix: "publish-moment", ext: format)
            let data = try Data(contentsOf: copied)

            let response: UpdateTrackDraftResponse = try await postPublish(
                Endpoints.updateNicheTrackDraft(id: draft.id),
                body: UpdateTrackDraftBody(
                    moment: PublishMomentUploadBody(hasMoment: true, momentFormat: format)
                )
            )

            guard let upload = response.upload?.moment else {
                throw PublishMusicError.uploadFailed
            }

            try await putFile(data: data, upload: upload)

            updateSingleTrack {
                $0.pendingMomentURL = copied
                $0.momentUpload = .uploaded
            }
            uploadToasts.complete(toastID)
        } catch {
            updateSingleTrack { $0.momentUpload = .failed(error.localizedDescription) }
            uploadToasts.fail(toastID)
            errorMessage = error.localizedDescription
        }
    }

    func updateSingleCredits(_ credits: [PublishCreditEntry]) async {
        updateSingleTrack { $0.credits = credits }
        guard case .single(let draft) = flow else { return }

        do {
            let _: UpdateTrackDraftResponse = try await postPublish(
                Endpoints.updateNicheTrackDraft(id: draft.id),
                body: UpdateTrackDraftBody(credits: creditsBody(from: credits))
            )
            PublishHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
            PublishHaptics.error()
        }
    }

    func showSingleReview() {
        guard case .single(let draft) = flow else { return }
        flow = .reviewSingle(draft)
    }

    func publishSingle() async -> PublishMusicDestination? {
        guard case .reviewSingle(let draft) = flow else { return nil }
        guard draft.isReadyToPublish else { return nil }

        isBusy = true
        publishProgress = 0.2
        errorMessage = nil

        do {
            await syncSingleMetadata(includeCredits: true)
            publishProgress = 0.55

            let response: PublishIdResponse = try await api.request(
                Endpoints.publishNicheTrackDraft(id: draft.id),
                method: .post
            )

            singleDraftSummaries.removeAll { $0.id == draft.id }
            publishProgress = 1
            didPublish = true
            PublishHaptics.success()
            isBusy = false
            return .track(response.id)
        } catch {
            errorMessage = error.localizedDescription
            isBusy = false
            PublishHaptics.error()
            return nil
        }
    }

    // MARK: - Release flow

    func beginRelease(type: PublishReleaseType) async {
        isBusy = true
        errorMessage = nil

        do {
            let response: CreateReleaseDraftResponse = try await postPublish(
                Endpoints.createNicheReleaseDraft,
                body: CreateReleaseDraftBody(releaseType: type.rawValue)
            )

            flow = .release(
                PublishReleaseDraft(id: response.id, releaseType: type)
            )
            isBusy = false
            PublishHaptics.tap()
        } catch {
            errorMessage = error.localizedDescription
            isBusy = false
            PublishHaptics.error()
        }
    }

    func updateRelease(_ mutate: (inout PublishReleaseDraft) -> Void) {
        guard case .release(var draft) = flow else { return }
        mutate(&draft)
        flow = .release(draft)
    }

    func scheduleReleaseMetadataSync() {
        guard case .release(let draft) = flow else { return }
        scheduleMetadataSync(key: "release-\(draft.id)") { [weak self] in
            await self?.syncReleaseMetadata()
        }
    }

    func syncReleaseMetadata() async {
        guard case .release(let draft) = flow else { return }

        let body = UpdateReleaseDraftBody(
            name: trimmedOrNil(draft.name),
            releaseDate: PublishDateFormatting.apiString(from: draft.releaseDate),
            visibility: draft.visibility.rawValue,
            releaseType: draft.releaseType.rawValue
        )

        do {
            let response: UpdateReleaseDraftResponse = try await postPublish(
                Endpoints.updateNicheReleaseDraft(releaseDraftId: draft.id),
                body: body
            )

            if let artworkURL = response.draft?.artworkUrl {
                updateRelease { $0.artworkURL = artworkURL }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func uploadReleaseArtwork(jpegData: Data) async {
        guard case .release(let draft) = flow else { return }

        updateRelease {
            $0.pendingArtworkJPEG = jpegData
            $0.artworkUpload = .uploading
        }

        let toastID = uploadToasts.begin("Uploading artwork")

        do {
            let response: UpdateReleaseDraftResponse = try await postPublish(
                Endpoints.updateNicheReleaseDraft(releaseDraftId: draft.id),
                body: UpdateReleaseDraftBody(
                    image: PublishImageUploadBody(hasImage: true, imageFormat: "jpeg")
                )
            )

            guard let upload = response.upload?.image else {
                throw PublishMusicError.uploadFailed
            }

            try await putFile(data: jpegData, upload: upload)

            updateRelease {
                $0.artworkURL = upload.publicUrl
                $0.artworkUpload = .uploaded
            }
            uploadToasts.complete(toastID)
            await syncReleaseMetadata()
        } catch {
            updateRelease { $0.artworkUpload = .failed(error.localizedDescription) }
            uploadToasts.fail(toastID)
            errorMessage = error.localizedDescription
        }
    }

    func addReleaseTrack(from audioURL: URL) async {
        guard case .release(let draft) = flow else { return }

        isBusy = true
        errorMessage = nil

        do {
            guard let format = PublishMediaSupport.musicFormat(for: audioURL) else {
                throw PublishMusicError.unsupportedAudioFormat
            }

            let copied = try PublishMediaSupport.copiedFileURL(
                from: audioURL,
                prefix: "publish-audio",
                ext: format
            )
            let durationMs = await PublishMediaSupport.audioDurationMs(for: copied)

            let response: CreateTrackDraftResponse = try await postPublish(
                Endpoints.createNicheReleaseTrackDraft(releaseDraftId: draft.id),
                body: CreateTrackDraftBody(musicFormat: format)
            )

            var track = PublishTrackDraft(
                id: response.id,
                localAudioURL: copied,
                audioFileLabel: audioURL.lastPathComponent,
                visibility: draft.visibility,
                durationMs: durationMs,
                trackNumber: draft.tracks.count + 1
            )
            track.releaseDate = draft.releaseDate

            updateRelease { release in
                release.tracks.append(track)
                release.reassignTrackNumbers()
            }

            let releaseDraftId = draft.id
            let trackId = response.id

            isBusy = false

            startAudioUpload(
                trackId: trackId,
                fileURL: copied,
                upload: response.upload,
                releaseDraftId: releaseDraftId
            ) { [weak self] state in
                self?.updateReleaseTrack(id: trackId) { $0.audioUpload = state }
            }

            await syncReleaseTrackMetadata(trackId: trackId)
            PublishHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
            isBusy = false
            PublishHaptics.error()
        }
    }

    func updateReleaseTrack(id: String, _ mutate: (inout PublishTrackDraft) -> Void) {
        guard case .release(var draft) = flow else { return }
        guard let index = draft.tracks.firstIndex(where: { $0.id == id }) else { return }
        mutate(&draft.tracks[index])
        flow = .release(draft)
    }

    func moveReleaseTracks(from source: IndexSet, to destination: Int) {
        updateRelease { release in
            release.tracks = Self.reordered(
                release.tracks,
                from: source,
                to: destination
            )
            release.reassignTrackNumbers()
        }
        Task {
            for track in releaseTracks {
                await syncReleaseTrackMetadata(trackId: track.id)
            }
        }
    }

    func removeReleaseTrack(id: String) {
        guard case .release(let draft) = flow else { return }
        let releaseDraftId = draft.id

        updateRelease { release in
            release.tracks.removeAll { $0.id == id }
            release.reassignTrackNumbers()
        }

        Task {
            try? await api.requestVoid(
                Endpoints.deleteNicheReleaseTrackDraft(
                    releaseDraftId: releaseDraftId,
                    trackDraftId: id
                ),
                method: .post
            )
        }
    }

    var releaseTracks: [PublishTrackDraft] {
        if case .release(let draft) = flow { return draft.tracks }
        return []
    }

    func scheduleReleaseTrackMetadataSync(trackId: String) {
        scheduleMetadataSync(key: "release-track-\(trackId)") { [weak self] in
            await self?.syncReleaseTrackMetadata(trackId: trackId)
        }
    }

    func syncReleaseTrackMetadata(trackId: String, includeCredits: Bool = false) async {
        guard case .release(let draft) = flow else { return }
        guard let track = draft.tracks.first(where: { $0.id == trackId }) else { return }

        var body = UpdateTrackDraftBody(
            name: trimmedOrNil(track.name),
            releaseDate: PublishDateFormatting.apiString(from: draft.releaseDate),
            explicit: track.explicit,
            durationMs: track.durationMs,
            bpm: track.bpmValue,
            visibility: track.visibility.rawValue,
            trackNumber: track.trackNumber
        )

        if includeCredits {
            body.credits = creditsBody(from: track.credits)
        }

        do {
            let response: UpdateTrackDraftResponse = try await postPublish(
                Endpoints.updateNicheReleaseTrackDraft(
                    releaseDraftId: draft.id,
                    trackDraftId: trackId
                ),
                body: body
            )

            if let artworkURL = response.draft?.artworkUrl {
                updateReleaseTrack(id: trackId) { $0.artworkURL = artworkURL }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func uploadReleaseTrackArtwork(trackId: String, jpegData: Data) async {
        guard case .release(let draft) = flow else { return }

        updateReleaseTrack(id: trackId) {
            $0.pendingArtworkJPEG = jpegData
            $0.hasCustomArtwork = true
            $0.artworkUpload = .uploading
        }

        let toastID = uploadToasts.begin("Uploading track artwork")

        do {
            let response: UpdateTrackDraftResponse = try await postPublish(
                Endpoints.updateNicheReleaseTrackDraft(
                    releaseDraftId: draft.id,
                    trackDraftId: trackId
                ),
                body: UpdateTrackDraftBody(
                    trackNumber: draft.tracks.first(where: { $0.id == trackId })?.trackNumber ?? 1,
                    image: PublishImageUploadBody(hasImage: true, imageFormat: "jpeg")
                )
            )

            guard let upload = response.upload?.image else {
                throw PublishMusicError.uploadFailed
            }

            try await putFile(data: jpegData, upload: upload)

            updateReleaseTrack(id: trackId) {
                $0.artworkURL = upload.publicUrl
                $0.artworkUpload = .uploaded
            }
            uploadToasts.complete(toastID)
            await syncReleaseTrackMetadata(trackId: trackId)
        } catch {
            updateReleaseTrack(id: trackId) {
                $0.artworkUpload = .failed(error.localizedDescription)
            }
            uploadToasts.fail(toastID)
            errorMessage = error.localizedDescription
        }
    }

    func clearReleaseTrackArtwork(trackId: String) {
        updateReleaseTrack(id: trackId) {
            $0.hasCustomArtwork = false
            $0.pendingArtworkJPEG = nil
            $0.artworkURL = nil
            $0.artworkUpload = .waiting
        }
        PublishHaptics.selection()
    }

    func uploadReleaseTrackMoment(trackId: String, from url: URL) async {
        guard case .release(let draft) = flow else { return }
        guard let format = PublishMediaSupport.videoFormat(for: url) else {
            errorMessage = PublishMusicError.unsupportedVideoFormat.localizedDescription
            return
        }

        updateReleaseTrack(id: trackId) {
            $0.pendingMomentURL = url
            $0.momentUpload = .uploading
        }

        let toastID = uploadToasts.begin("Uploading moment")

        do {
            let copied = try PublishMediaSupport.copiedFileURL(from: url, prefix: "publish-moment", ext: format)
            let data = try Data(contentsOf: copied)
            let trackNumber = draft.tracks.first(where: { $0.id == trackId })?.trackNumber ?? 1

            let response: UpdateTrackDraftResponse = try await postPublish(
                Endpoints.updateNicheReleaseTrackDraft(
                    releaseDraftId: draft.id,
                    trackDraftId: trackId
                ),
                body: UpdateTrackDraftBody(
                    trackNumber: trackNumber,
                    moment: PublishMomentUploadBody(hasMoment: true, momentFormat: format)
                )
            )

            guard let upload = response.upload?.moment else {
                throw PublishMusicError.uploadFailed
            }

            try await putFile(data: data, upload: upload)

            updateReleaseTrack(id: trackId) {
                $0.pendingMomentURL = copied
                $0.momentUpload = .uploaded
            }
            uploadToasts.complete(toastID)
        } catch {
            updateReleaseTrack(id: trackId) {
                $0.momentUpload = .failed(error.localizedDescription)
            }
            uploadToasts.fail(toastID)
            errorMessage = error.localizedDescription
        }
    }

    func updateReleaseTrackCredits(trackId: String, credits: [PublishCreditEntry]) async {
        updateReleaseTrack(id: trackId) { $0.credits = credits }
        guard case .release(let draft) = flow else { return }

        do {
            let trackNumber = draft.tracks.first(where: { $0.id == trackId })?.trackNumber ?? 1
            let _: UpdateTrackDraftResponse = try await postPublish(
                Endpoints.updateNicheReleaseTrackDraft(
                    releaseDraftId: draft.id,
                    trackDraftId: trackId
                ),
                body: UpdateTrackDraftBody(
                    trackNumber: trackNumber,
                    credits: creditsBody(from: credits)
                )
            )
            PublishHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
            PublishHaptics.error()
        }
    }

    func showReleaseReview() {
        guard case .release(let draft) = flow else { return }
        flow = .reviewRelease(draft)
    }

    func publishRelease() async -> PublishMusicDestination? {
        guard case .reviewRelease(let draft) = flow else { return nil }
        guard draft.isReadyToPublish else { return nil }

        isBusy = true
        publishProgress = 0.15
        errorMessage = nil

        do {
            await syncReleaseMetadata()

            for track in draft.tracks {
                await syncReleaseTrackMetadata(trackId: track.id, includeCredits: true)
            }

            publishProgress = 0.65

            let response: PublishIdResponse = try await api.request(
                Endpoints.publishNicheReleaseDraft(releaseDraftId: draft.id),
                method: .post
            )

            releaseDraftSummaries.removeAll { $0.id == draft.id }
            publishProgress = 1
            didPublish = true
            PublishHaptics.success()
            isBusy = false
            return .release(response.id)
        } catch {
            errorMessage = error.localizedDescription
            isBusy = false
            PublishHaptics.error()
            return nil
        }
    }

    // MARK: - Published editing

    func updatePublishedTrack(
        trackId: String,
        name: String,
        explicit: Bool,
        bpm: Int?,
        visibility: PublishVisibility,
        credits: [PublishCreditEntry],
        artworkJPEG: Data?,
        momentURL: URL?
    ) async throws {
        var body = UpdatePublishedTrackBody(
            name: trimmedOrNil(name),
            explicit: explicit,
            bpm: bpm,
            visibility: visibility.rawValue,
            credits: creditsBody(from: credits)
        )

        if artworkJPEG != nil {
            body.image = PublishImageUploadBody(hasImage: true, imageFormat: "jpeg")
        }

        if let momentURL, PublishMediaSupport.videoFormat(for: momentURL) != nil {
            body.moment = PublishMomentUploadBody(
                hasMoment: true,
                momentFormat: PublishMediaSupport.videoFormat(for: momentURL)!
            )
        }

        let response: UpdatePublishedTrackResponse = try await postPublish(
            Endpoints.updatePublishedNicheTrack(trackId: trackId),
            body: body
        )

        if let artworkJPEG, let upload = response.upload?.image {
            let toastID = uploadToasts.begin("Uploading artwork")
            do {
                try await putFile(data: artworkJPEG, upload: upload)
                uploadToasts.complete(toastID)
            } catch {
                uploadToasts.fail(toastID)
                throw error
            }
        }

        if let momentURL, let upload = response.upload?.moment {
            let toastID = uploadToasts.begin("Uploading moment")
            do {
                let data = try Data(contentsOf: momentURL)
                try await putFile(data: data, upload: upload)
                uploadToasts.complete(toastID)
            } catch {
                uploadToasts.fail(toastID)
                throw error
            }
        }
    }

    func updatePublishedTrackCredits(
        trackId: String,
        credits: [PublishCreditEntry]
    ) async throws {
        let body = UpdatePublishedTrackBody(credits: creditsBody(from: credits))
        let _: UpdatePublishedTrackResponse = try await postPublish(
            Endpoints.updatePublishedNicheTrack(trackId: trackId),
            body: body
        )
    }

    func deletePublishedTrack(trackId: String) async throws {
        try await api.requestVoid(
            Endpoints.deletePublishedNicheTrack(trackId: trackId),
            method: .post
        )
    }

    func updatePublishedRelease(
        releaseId: String,
        name: String,
        visibility: PublishVisibility,
        artworkJPEG: Data?
    ) async throws -> NicheReleaseSummary {
        var body = UpdatePublishedReleaseBody(
            name: trimmedOrNil(name),
            visibility: visibility.rawValue
        )

        if let artworkJPEG {
            body.image = PublishImageUploadBody(hasImage: true, imageFormat: "jpeg")
            let response: UpdatePublishedReleaseResponse = try await postPublish(
                Endpoints.updatePublishedNicheRelease(releaseId: releaseId),
                body: body
            )
            if let upload = response.upload?.image {
                try await putFile(data: artworkJPEG, upload: upload)
            }
            let final: UpdatePublishedReleaseResponse = try await postPublish(
                Endpoints.updatePublishedNicheRelease(releaseId: releaseId),
                body: UpdatePublishedReleaseBody(
                    name: trimmedOrNil(name),
                    visibility: visibility.rawValue
                )
            )
            return final.release
        }

        let response: UpdatePublishedReleaseResponse = try await postPublish(
            Endpoints.updatePublishedNicheRelease(releaseId: releaseId),
            body: body
        )
        return response.release
    }

    func deletePublishedRelease(releaseId: String) async throws {
        try await api.requestVoid(
            Endpoints.deletePublishedNicheRelease(releaseId: releaseId),
            method: .post
        )
    }

    func searchProfiles(query: String) async -> [GlobalSearchProfileResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        do {
            let response: GlobalSearchResponse = try await api.request(
                Endpoints.globalSearch,
                method: .get,
                query: ["q": trimmed, "perTypeLimit": "12"]
            )
            return response.results.profiles
        } catch {
            return []
        }
    }

    // MARK: - Private

    private func startAudioUpload(
        trackId: String,
        fileURL: URL,
        upload: PresignedUploadInfo,
        releaseDraftId: String?,
        onStateChange: @escaping (PublishUploadState) -> Void
    ) {
        onStateChange(.uploading)
        let toastID = uploadToasts.begin("Uploading audio")

        Task {
            do {
                let data = try Data(contentsOf: fileURL)
                try await putFile(data: data, upload: upload)
                onStateChange(.uploaded)
                uploadToasts.complete(toastID)

                if releaseDraftId != nil {
                    await syncReleaseTrackMetadata(trackId: trackId)
                } else {
                    await syncSingleMetadata()
                }
            } catch {
                onStateChange(.failed(error.localizedDescription))
                uploadToasts.fail(toastID)
            }
        }
    }

    private func putFile(data: Data, upload: PresignedUploadInfo) async throws {
        guard data.count <= upload.maxBytes else {
            throw PublishMusicError.fileTooLarge
        }

        guard let uploadURL = URL(string: upload.uploadUrl) else {
            throw PublishMusicError.invalidUploadURL
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue(upload.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PublishMusicError.uploadFailed
        }
    }

    private func scheduleMetadataSync(key: String, action: @escaping () async -> Void) {
        metadataSyncTasks[key]?.cancel()
        metadataSyncTasks[key] = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await action()
        }
    }

    private func creditsBody(from credits: [PublishCreditEntry]) -> PublishCreditsBody {
        PublishCreditsBody(
            hasCredits: true,
            artists: credits.map {
                PublishCreditArtistBody(artistId: $0.artistId, isPrimary: $0.isPrimary)
            }
        )
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func reordered<T>(
        _ items: [T],
        from source: IndexSet,
        to destination: Int
    ) -> [T] {
        var result = items
        let moving = source.sorted().map { result[$0] }
        for index in source.sorted(by: >) {
            result.remove(at: index)
        }
        var target = destination
        for index in source where index < destination {
            target -= 1
        }
        result.insert(contentsOf: moving, at: target)
        return result
    }
}
