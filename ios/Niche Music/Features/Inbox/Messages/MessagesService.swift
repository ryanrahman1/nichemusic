//
//  MessagesService.swift
//  Niche Music
//

import Foundation

@MainActor
final class MessagesService {
    static let shared = MessagesService()

    private let api = APIClient.shared
    private var inboxInflight: Task<[InboxRow], Error>?

    private init() {}

    func fetchInbox() async throws -> [InboxRow] {
        if let inboxInflight {
            return try await inboxInflight.value
        }

        let task = Task<[InboxRow], Error> {
            let response: InboxResponse = try await api.request(
                Endpoints.inbox,
                method: .get
            )
            return response.inbox
        }

        inboxInflight = task
        defer { inboxInflight = nil }

        return try await task.value
    }

    func fetchConversation(
        id: String,
        cursor: String? = nil,
        limit: Int = 40
    ) async throws -> ConversationPageResponse {
        var query: [String: String?] = [
            "limit": String(limit),
            "cursor": cursor,
        ]

        return try await api.request(
            Endpoints.conversation(id: id),
            method: .get,
            query: query
        )
    }

    func sendTextMessage(
        conversationId: String,
        clientId: String,
        text: String
    ) async throws -> ConversationMessage {
        let body = CreateTextMessageBody(
            conversationId: conversationId,
            clientId: clientId,
            kind: "text",
            text: text
        )

        let response: CreateMessageResponse = try await api.request(
            Endpoints.messagesCreate,
            method: .post,
            body: body,
            preserveBodyKeyNames: true
        )
        return response.message
    }

    func sendTrackShare(
        conversationId: String, clientId: String,
        trackId: String, caption: String? = nil
    ) async throws -> ConversationMessage {
        let body = CreateTrackShareBody(conversationId: conversationId, clientId: clientId,
                                       kind: "track_share", trackId: trackId, caption: caption)
        let response: CreateMessageResponse = try await api.request(
            Endpoints.messagesCreate, method: .post, body: body, preserveBodyKeyNames: true)
        return response.message
    }

    func sendAlbumShare(
        conversationId: String, clientId: String,
        albumId: String, caption: String? = nil
    ) async throws -> ConversationMessage {
        let body = CreateAlbumShareBody(conversationId: conversationId, clientId: clientId,
                                       kind: "album_share", albumId: albumId, caption: caption)
        let response: CreateMessageResponse = try await api.request(
            Endpoints.messagesCreate, method: .post, body: body, preserveBodyKeyNames: true)
        return response.message
    }

    func sendArtistShare(
        conversationId: String, clientId: String,
        artistId: String, caption: String? = nil
    ) async throws -> ConversationMessage {
        let body = CreateArtistShareBody(conversationId: conversationId, clientId: clientId,
                                        kind: "artist_share", artistId: artistId, caption: caption)
        let response: CreateMessageResponse = try await api.request(
            Endpoints.messagesCreate, method: .post, body: body, preserveBodyKeyNames: true)
        return response.message
    }

    func sendProfileShare(
        conversationId: String, clientId: String,
        userId: String, caption: String? = nil
    ) async throws -> ConversationMessage {
        let body = CreateProfileShareBody(conversationId: conversationId, clientId: clientId,
                                         kind: "profile_share", userId: userId, caption: caption)
        let response: CreateMessageResponse = try await api.request(
            Endpoints.messagesCreate, method: .post, body: body, preserveBodyKeyNames: true)
        return response.message
    }

    func sendGif(
        conversationId: String, clientId: String,
        gifUrl: String, width: Int, height: Int,
        provider: String = "giphy", caption: String? = nil
    ) async throws -> ConversationMessage {
        let body = CreateGifBody(conversationId: conversationId, clientId: clientId,
                                 kind: "gif", gifUrl: gifUrl, width: width, height: height,
                                 provider: provider, caption: caption)
        let response: CreateMessageResponse = try await api.request(
            Endpoints.messagesCreate, method: .post, body: body, preserveBodyKeyNames: true)
        return response.message
    }

    // MARK: – Apple Music resolve helpers
    // Maps an Apple Music source ID → internal DB ID, upserting if not yet stored.

    func resolveAppleSong(_ sourceId: String) async throws -> String {
        let response: AppleSongIdLookupResponse = try await api.request(
            Endpoints.appleMusicSong(id: sourceId), method: .get)
        return response.track.id
    }

    func resolveAppleAlbum(_ sourceId: String) async throws -> String {
        let response: AppleAlbumLookupResponse = try await api.request(
            Endpoints.appleMusicAlbum(id: sourceId), method: .get)
        return response.album.id
    }

    func resolveAppleArtist(_ sourceId: String) async throws -> String {
        let response: AppleArtistLookupResponse = try await api.request(
            Endpoints.appleMusicArtist(id: sourceId), method: .get)
        return response.artist.id
    }

    // MARK: – User lookup

    func lookupUser(username: String) async throws -> MessageUserSummary {
        let response: MessageUserLookupResponse = try await api.request(
            Endpoints.user(username: username), method: .get)
        return response.user
    }

    // MARK: – Music search (songs + albums + artists in one call)

    func searchAppleMusic(query: String, types: String = "songs,albums,artists") async throws -> AppleMusicSearchResults? {
        let response: AppleMusicSearchResponse = try await api.request(
            Endpoints.appleMusicSearch,
            method: .get,
            query: ["q": query, "types": types]
        )
        return response.data.results
    }

    func markRead(conversationId: String, messageId: String) async throws {
        let body = MarkMessageReadBody(
            conversationId: conversationId,
            messageId: messageId
        )

        let _: MarkMessageReadResponse = try await api.request(
            Endpoints.messagesRead,
            method: .post,
            body: body,
            preserveBodyKeyNames: true
        )
    }

    func ensureDM(otherUserId: String) async throws -> String {
        let body = EnsureDMBody(otherUserId: otherUserId)
        let response: EnsureDMResponse = try await api.request(
            Endpoints.messagesDmEnsure,
            method: .post,
            body: body,
            preserveBodyKeyNames: true
        )
        return response.conversationId
    }

    func fetchFriends() async throws -> [MessageUserSummary] {
        let response: FriendsResponse = try await api.request(
            Endpoints.myFriends,
            method: .get
        )
        return response.friends
    }

    static func makeClientId() -> String {
        let suffix = String(Int.random(in: 1000...9999))
        return "c_\(Int(Date().timeIntervalSince1970 * 1000))_\(suffix)"
    }
}
