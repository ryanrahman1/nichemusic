//
//  PublishMusicModels.swift
//  Niche Music
//

import Foundation

enum PublishReleaseType: String, CaseIterable, Identifiable, Codable {
    case ep
    case album

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ep: "EP"
        case .album: "Album"
        }
    }
}

enum PublishVisibility: String, CaseIterable, Identifiable, Codable {
    case `public`
    case `private`

    var id: String { rawValue }

    var label: String {
        switch self {
        case .public: "Public"
        case .private: "Private"
        }
    }
}

enum PublishUploadState: Equatable {
    case waiting
    case uploading
    case uploaded
    case failed(String)

    var isUploaded: Bool {
        if case .uploaded = self { return true }
        return false
    }

    var isUploading: Bool {
        if case .uploading = self { return true }
        return false
    }

    var statusLabel: String {
        switch self {
        case .waiting: "Waiting"
        case .uploading: "Uploading…"
        case .uploaded: "Uploaded"
        case .failed: "Failed"
        }
    }
}

struct PublishCreditEntry: Identifiable, Equatable {
    let id: String
    var artistId: String
    var username: String
    var displayName: String?
    var avatarUrl: String?
    var isPrimary: Bool

    init(
        id: String = UUID().uuidString,
        artistId: String,
        username: String,
        displayName: String? = nil,
        avatarUrl: String? = nil,
        isPrimary: Bool = false
    ) {
        self.id = id
        self.artistId = artistId
        self.username = username
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.isPrimary = isPrimary
    }

    static func from(_ profile: GlobalSearchProfileResult, isPrimary: Bool = false) -> PublishCreditEntry {
        PublishCreditEntry(
            artistId: profile.id,
            username: profile.username,
            displayName: profile.displayName,
            avatarUrl: profile.avatarUrl,
            isPrimary: isPrimary
        )
    }

    static func from(_ credit: NicheTrackCredit) -> PublishCreditEntry? {
        guard let artistId = credit.artistId ?? credit.artist?.id,
              let username = credit.artist?.username else {
            return nil
        }
        return PublishCreditEntry(
            artistId: artistId,
            username: username,
            displayName: credit.artist?.displayName,
            avatarUrl: credit.artist?.avatarUrl,
            isPrimary: credit.isPrimary ?? false
        )
    }
}

struct PublishTrackDraft: Identifiable, Equatable {
    var id: String
    var localAudioURL: URL?
    var audioFileLabel: String?
    var audioUpload: PublishUploadState = .waiting
    var name: String = ""
    var releaseDate: Date = Date()
    var visibility: PublishVisibility = .public
    var durationMs: Int?
    var bpmText: String = ""
    var explicit: Bool = false
    var trackNumber: Int = 1
    var pendingArtworkJPEG: Data?
    var artworkURL: String?
    var hasCustomArtwork: Bool = false
    var artworkUpload: PublishUploadState = .waiting
    var pendingMomentURL: URL?
    var momentUpload: PublishUploadState = .waiting
    var credits: [PublishCreditEntry] = []

    var bpmValue: Int? {
        let trimmed = bpmText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    func displayArtworkURL(releaseArtworkURL: String?) -> String? {
        if hasCustomArtwork {
            return artworkURL
        }
        return releaseArtworkURL
    }

    func resolvedArtworkPreview(releaseArtworkJPEG: Data?) -> Data? {
        if hasCustomArtwork {
            return pendingArtworkJPEG
        }
        return releaseArtworkJPEG
    }

    var isReadyToPublish: Bool {
        audioUpload.isUploaded
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && durationMs != nil
    }

    func validationIssues(releaseArtworkURL: String? = nil) -> [String] {
        var issues: [String] = []
        if !audioUpload.isUploaded { issues.append("Audio not uploaded") }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("Track name required") }
        if durationMs == nil { issues.append("Duration required") }
        return issues
    }
}

struct PublishReleaseDraft: Identifiable, Equatable {
    var id: String
    var releaseType: PublishReleaseType
    var name: String = ""
    var releaseDate: Date = Date()
    var visibility: PublishVisibility = .public
    var pendingArtworkJPEG: Data?
    var artworkURL: String?
    var artworkUpload: PublishUploadState = .waiting
    var tracks: [PublishTrackDraft] = []

    mutating func reassignTrackNumbers() {
        for index in tracks.indices {
            tracks[index].trackNumber = index + 1
        }
    }

    var isReadyToPublish: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && artworkUpload.isUploaded
            && !tracks.isEmpty
            && tracks.allSatisfy(\.isReadyToPublish)
    }

    func validationIssues() -> [String] {
        var issues: [String] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Release name required")
        }
        if !artworkUpload.isUploaded {
            issues.append("Release artwork required")
        }
        if tracks.isEmpty {
            issues.append("Add at least one track")
        }
        for track in tracks {
            let trackIssues = track.validationIssues(releaseArtworkURL: artworkURL)
            if !trackIssues.isEmpty {
                issues.append("Track \(track.trackNumber): \(trackIssues.joined(separator: ", "))")
            }
        }
        return issues
    }
}

struct PresignedUploadInfo: Decodable {
    let uploadUrl: String
    let objectKey: String
    let publicUrl: String
    let contentType: String
    let maxBytes: Int
}

struct CreateTrackDraftBody: Encodable {
    let musicFormat: String
}

struct CreateTrackDraftResponse: Decodable {
    let id: String
    let upload: PresignedUploadInfo
}

struct CreateReleaseDraftBody: Encodable {
    let releaseType: String
}

struct CreateReleaseDraftResponse: Decodable {
    let id: String
}

struct PublishImageUploadBody: Encodable {
    let hasImage: Bool
    let imageFormat: String

    enum CodingKeys: String, CodingKey {
        case hasImage
        case imageFormat
    }
}

struct PublishMomentUploadBody: Encodable {
    let hasMoment: Bool
    let momentFormat: String

    enum CodingKeys: String, CodingKey {
        case hasMoment
        case momentFormat
    }
}

struct PublishCreditArtistBody: Encodable {
    let artistId: String
    let isPrimary: Bool

    enum CodingKeys: String, CodingKey {
        case artistId
        case isPrimary
    }
}

struct PublishCreditsBody: Encodable {
    let hasCredits: Bool
    let artists: [PublishCreditArtistBody]

    enum CodingKeys: String, CodingKey {
        case hasCredits
        case artists
    }
}

struct UpdateTrackDraftBody: Encodable {
    var name: String?
    var releaseDate: String?
    var explicit: Bool?
    var durationMs: Int?
    var bpm: Int?
    var visibility: String?
    var trackNumber: Int?
    var image: PublishImageUploadBody?
    var moment: PublishMomentUploadBody?
    var credits: PublishCreditsBody?

    enum CodingKeys: String, CodingKey {
        case name
        case releaseDate = "release_date"
        case explicit
        case durationMs = "duration_ms"
        case bpm
        case visibility
        case trackNumber = "track_number"
        case image
        case moment
        case credits
    }
}

struct UpdateReleaseDraftBody: Encodable {
    var name: String?
    var releaseDate: String?
    var visibility: String?
    var releaseType: String?
    var image: PublishImageUploadBody?

    enum CodingKeys: String, CodingKey {
        case name
        case releaseDate = "release_date"
        case visibility
        case releaseType = "release_type"
        case image
    }
}

struct UpdateTrackDraftUploads: Decodable {
    let image: PresignedUploadInfo?
    let moment: PresignedUploadInfo?
}

struct UpdateTrackDraftResponse: Decodable {
    let id: String
    let draft: NicheTrackDraftRow?
    let upload: UpdateTrackDraftUploads?
}

struct UpdateReleaseDraftUploads: Decodable {
    let image: PresignedUploadInfo?
}

struct UpdateReleaseDraftResponse: Decodable {
    let id: String
    let draft: NicheReleaseDraftRow?
    let upload: UpdateReleaseDraftUploads?
}

struct NicheTrackDraftRow: Decodable {
    let id: String
    let artworkUrl: String?
    let momentUrl: String?
}

struct NicheReleaseDraftRow: Decodable {
    let id: String
    let artworkUrl: String?
}

struct PublishDraftCreditArtist: Decodable {
    let id: String
    let username: String
    let displayName: String?
    let avatarUrl: String?
}

struct PublishDraftCredit: Decodable {
    let artistId: String
    let isPrimary: Bool?
    let artist: PublishDraftCreditArtist?
}

struct PublishTrackDraftDetail: Decodable {
    let id: String
    let name: String?
    let artworkUrl: String?
    let musicUrl: String?
    let momentUrl: String?
    let releaseDate: String
    let explicit: Bool?
    let durationMs: Int?
    let bpm: Int?
    let visibility: String?
    let trackNumber: Int?
    let credits: [PublishDraftCredit]?
}

struct PublishDraftUploadStatus: Decodable {
    let music: Bool
    let artwork: Bool
    let moment: Bool
}

struct PublishTrackDraftSummary: Decodable, Identifiable, Equatable {
    let id: String
    let name: String?
    let artworkUrl: String?
    let releaseDate: String
    let durationMs: Int?
    let explicit: Bool?
    let visibility: String?
    let updatedAt: String?
}

struct PublishTrackDraftListResponse: Decodable {
    let drafts: [PublishTrackDraftSummary]
}

struct PublishSingleDraftDetailResponse: Decodable {
    let draft: PublishTrackDraftDetail
    let uploadStatus: PublishDraftUploadStatus
}

struct PublishReleaseDraftDetail: Decodable {
    let id: String
    let name: String?
    let artworkUrl: String?
    let releaseType: String
    let releaseDate: String
    let visibility: String?
}

struct PublishReleaseDraftSummary: Decodable, Identifiable, Equatable {
    let id: String
    let name: String?
    let artworkUrl: String?
    let releaseType: String
    let releaseDate: String
    let visibility: String?
    let updatedAt: String?
    let trackCount: Int
}

struct PublishReleaseDraftListResponse: Decodable {
    let drafts: [PublishReleaseDraftSummary]
}

struct PublishReleaseArtworkUploadStatus: Decodable {
    let artwork: Bool
}

struct PublishReleaseTrackUploadStatusEntry: Decodable {
    let id: String
    let uploadStatus: PublishDraftUploadStatus
}

struct PublishReleaseDraftUploadStatuses: Decodable {
    let release: PublishReleaseArtworkUploadStatus
    let tracks: [PublishReleaseTrackUploadStatusEntry]
}

struct PublishReleaseDraftDetailResponse: Decodable {
    let draft: PublishReleaseDraftDetail
    let tracks: [PublishTrackDraftDetail]
    let uploadStatus: PublishReleaseDraftUploadStatuses
}

enum PublishDraftMapping {
    static func trackDraft(
        from detail: PublishTrackDraftDetail,
        uploadStatus: PublishDraftUploadStatus
    ) -> PublishTrackDraft {
        var draft = PublishTrackDraft(
            id: detail.id,
            durationMs: detail.durationMs
        )
        draft.name = detail.name ?? ""
        if let date = PublishDateFormatting.date(from: detail.releaseDate) {
            draft.releaseDate = date
        }
        if let visibility = detail.visibility,
           let parsed = PublishVisibility(rawValue: visibility) {
            draft.visibility = parsed
        }
        draft.explicit = detail.explicit ?? false
        if let bpm = detail.bpm {
            draft.bpmText = String(bpm)
        }
        draft.trackNumber = detail.trackNumber ?? 1
        draft.artworkURL = detail.artworkUrl
        draft.hasCustomArtwork = detail.artworkUrl != nil
        draft.audioUpload = uploadStatus.music ? .uploaded : .waiting
        draft.artworkUpload = uploadStatus.artwork ? .uploaded : .waiting
        draft.momentUpload = uploadStatus.moment ? .uploaded : .waiting
        draft.credits = (detail.credits ?? []).compactMap { credit in
            guard let artist = credit.artist else { return nil }
            return PublishCreditEntry(
                artistId: credit.artistId,
                username: artist.username,
                displayName: artist.displayName,
                avatarUrl: artist.avatarUrl,
                isPrimary: credit.isPrimary ?? false
            )
        }
        return draft
    }

    static func releaseDraft(
        from response: PublishReleaseDraftDetailResponse
    ) -> PublishReleaseDraft? {
        guard let releaseType = PublishReleaseType(rawValue: response.draft.releaseType) else {
            return nil
        }

        let trackStatuses = Dictionary(
            uniqueKeysWithValues: response.uploadStatus.tracks.map { ($0.id, $0.uploadStatus) }
        )

        var draft = PublishReleaseDraft(
            id: response.draft.id,
            releaseType: releaseType
        )
        draft.name = response.draft.name ?? ""
        if let date = PublishDateFormatting.date(from: response.draft.releaseDate) {
            draft.releaseDate = date
        }
        if let visibility = response.draft.visibility,
           let parsed = PublishVisibility(rawValue: visibility) {
            draft.visibility = parsed
        }
        draft.artworkURL = response.draft.artworkUrl
        draft.artworkUpload = response.uploadStatus.release.artwork ? .uploaded : .waiting
        draft.tracks = response.tracks.map { track in
            let uploadStatus = trackStatuses[track.id] ?? PublishDraftUploadStatus(
                music: false,
                artwork: false,
                moment: false
            )
            return trackDraft(from: track, uploadStatus: uploadStatus)
        }
        return draft
    }
}

struct PublishIdResponse: Decodable {
    let id: String
}

enum PublishMusicDestination: Equatable, Identifiable {
    case track(String)
    case release(String)

    var id: String {
        switch self {
        case .track(let trackId):
            return "track-\(trackId)"
        case .release(let releaseId):
            return "release-\(releaseId)"
        }
    }
}

struct NicheReleaseSummary: Decodable {
    let id: String
    let name: String?
    let artworkUrl: String?
    let releaseType: String?
    let visibility: TrackVisiblity?
}

struct UpdatePublishedTrackBody: Encodable {
    var name: String?
    var explicit: Bool?
    var bpm: Int?
    var visibility: String?
    var image: PublishImageUploadBody?
    var moment: PublishMomentUploadBody?
    var credits: PublishCreditsBody?

    enum CodingKeys: String, CodingKey {
        case name
        case explicit
        case bpm
        case visibility
        case image
        case moment
        case credits
    }
}

struct UpdatePublishedTrackResponse: Decodable {
    let id: String
    let upload: UpdateTrackDraftUploads?
}

struct UpdatePublishedReleaseBody: Encodable {
    var name: String?
    var visibility: String?
    var releaseType: String?
    var image: PublishImageUploadBody?

    enum CodingKeys: String, CodingKey {
        case name
        case visibility
        case releaseType = "release_type"
        case image
    }
}

struct UpdatePublishedReleaseResponse: Decodable {
    let id: String
    let release: NicheReleaseSummary
    let upload: UpdateReleaseDraftUploads?
}

enum PublishMusicError: LocalizedError {
    case unsupportedAudioFormat
    case unsupportedVideoFormat
    case fileTooLarge
    case uploadFailed
    case invalidUploadURL
    case draftNotCreated
    case publishFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedAudioFormat: "That audio format isn't supported."
        case .unsupportedVideoFormat: "That video format isn't supported."
        case .fileTooLarge: "File exceeds the upload size limit."
        case .uploadFailed: "Upload failed. Try again."
        case .invalidUploadURL: "Couldn't start upload."
        case .draftNotCreated: "Couldn't create draft."
        case .publishFailed(let message): message
        }
    }
}

enum PublishDateFormatting {
    static let apiFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func apiString(from date: Date) -> String {
        apiFormatter.string(from: date)
    }

    static func date(from apiString: String) -> Date? {
        apiFormatter.date(from: apiString)
    }
}
