//
//  AuxBattleStore.swift
//  Niche Music
//

import Foundation
import Combine

@MainActor
final class AuxBattleStore: ObservableObject {
    @Published private(set) var roomState: AuxRoomState?
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var lastError: String?
    @Published private(set) var wsConnected = false
    @Published var toastMessage: String?

    let snippetPlayer = AuxBattleSnippetPlayer()

    private let api = APIClient.shared
    private let webSocket = AuxWebSocketService()
    private var refreshTask: Task<Void, Never>?
    private var currentUserId: String?
    private var cancellables = Set<AnyCancellable>()

    init() {
        snippetPlayer.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func setCurrentUserId(_ id: String?) {
        currentUserId = id
    }

    func resetSession() {
        disconnectWebSocket()
        snippetPlayer.stop()
        roomState = nil
        lastError = nil
        toastMessage = nil
        isLoading = false
        isSubmitting = false
    }

    func clearError() {
        lastError = nil
    }

    // MARK: - Room lifecycle

    func createRoom(
        prompt: String,
        maxPlayers: Int = 8,
        snippetLengthSeconds: Int = 15,
        songSource: AuxSongSource = .any
    ) async -> Bool {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let body = AuxCreateRoomBody(
                prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                maxPlayers: maxPlayers,
                snippetLengthSeconds: snippetLengthSeconds,
                songSource: songSource
            )
            let state: AuxRoomState = try await auxPOST(
                Endpoints.auxCreateRoom,
                body: body
            )
            applyRoomState(state)
            connectWebSocket(roomId: state.room.id)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func joinRoom(code: String) async -> Bool {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let state: AuxRoomState = try await auxPOST(
                Endpoints.auxJoinRoom,
                body: AuxJoinRoomBody(code: code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
            )
            applyRoomState(state)
            connectWebSocket(roomId: state.room.id)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func leaveRoom() async {
        guard let roomId = roomState?.room.id else {
            resetSession()
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let _: AuxLeaveResponse = try await api.request(
                Endpoints.auxLeaveRoom(roomId: roomId),
                method: .post
            )
        } catch {
            // Still reset locally even if API fails
        }

        resetSession()
    }

    func refreshRoom() async {
        guard let roomId = roomState?.room.id else { return }

        do {
            let state: AuxRoomState = try await api.request(
                Endpoints.auxRoom(roomId: roomId),
                method: .get
            )
            applyRoomState(state)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func updateSettings(
        prompt: String?,
        maxPlayers: Int?,
        snippetLengthSeconds: Int?,
        songSource: AuxSongSource?
    ) async -> Bool {
        guard let roomId = roomState?.room.id else { return false }

        isSubmitting = true
        lastError = nil
        defer { isSubmitting = false }

        do {
            let body = AuxUpdateSettingsBody(
                prompt: prompt,
                maxPlayers: maxPlayers,
                snippetLengthSeconds: snippetLengthSeconds,
                songSource: songSource
            )
            let state: AuxRoomState = try await auxPOST(
                Endpoints.auxUpdateSettings(roomId: roomId),
                body: body
            )
            applyRoomState(state)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Game actions

    func startSubmissions() async -> Bool {
        await performRoomAction { Endpoints.auxStartSubmissions(roomId: $0) }
    }

    func submitSong(source: AuxSubmissionSource, nicheTrackId: String?, trackId: String?, snippetStartMs: Int) async -> Bool {
        guard let roomId = roomState?.room.id else { return false }

        isSubmitting = true
        lastError = nil
        defer { isSubmitting = false }

        do {
            let body = AuxSubmitSongBody(
                source: source,
                nicheTrackId: nicheTrackId,
                trackId: trackId,
                snippetStartMs: snippetStartMs
            )
            let state: AuxRoomState = try await auxPOST(
                Endpoints.auxSubmitSong(roomId: roomId),
                body: body
            )
            applyRoomState(state)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func createBracket() async -> Bool {
        await performRoomAction { Endpoints.auxCreateBracket(roomId: $0) }
    }

    func startBracket() async -> Bool {
        await performRoomAction { Endpoints.auxStartBracket(roomId: $0) }
    }

    func startMatchupA(matchupId: String) async -> Bool {
        guard let roomId = roomState?.room.id else { return false }
        return await performRoomAction { _ in
            Endpoints.auxStartMatchupA(roomId: roomId, matchupId: matchupId)
        }
    }

    func startMatchupB(matchupId: String) async -> Bool {
        guard let roomId = roomState?.room.id else { return false }
        return await performRoomAction { _ in
            Endpoints.auxStartMatchupB(roomId: roomId, matchupId: matchupId)
        }
    }

    func startVoting(matchupId: String) async -> Bool {
        guard let roomId = roomState?.room.id else { return false }
        return await performRoomAction { _ in
            Endpoints.auxStartVoting(roomId: roomId, matchupId: matchupId)
        }
    }

    func vote(matchupId: String, submissionId: String) async -> Bool {
        guard let roomId = roomState?.room.id else { return false }

        isSubmitting = true
        lastError = nil
        defer { isSubmitting = false }

        do {
            let state: AuxRoomState = try await auxPOST(
                Endpoints.auxVote(roomId: roomId, matchupId: matchupId),
                body: AuxVoteBody(submissionId: submissionId)
            )
            applyRoomState(state)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func revealMatchup(matchupId: String) async -> Bool {
        guard let roomId = roomState?.room.id else { return false }
        return await performRoomAction { _ in
            Endpoints.auxRevealMatchup(roomId: roomId, matchupId: matchupId)
        }
    }

    func playAgain() async -> Bool {
        guard let oldRoomId = roomState?.room.id else { return false }
        let success = await performRoomAction { Endpoints.auxPlayAgain(roomId: $0) }
        if success, let newRoomId = roomState?.room.id, newRoomId != oldRoomId {
            connectWebSocket(roomId: newRoomId)
            toastMessage = "Joined rematch lobby"
        }
        return success
    }

    func createRematch() async -> Bool {
        guard let roomId = roomState?.room.id else { return false }

        isSubmitting = true
        lastError = nil
        defer { isSubmitting = false }

        do {
            let response: AuxRematchCreateResponse = try await auxPOST(
                Endpoints.auxCreateRematch(roomId: roomId)
            )
            applyRoomState(response.room)
            connectWebSocket(roomId: response.room.room.id)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - WebSocket

    private func connectWebSocket(roomId: String) {
        disconnectWebSocket()
        webSocket.connect(roomId: roomId) { [weak self] event in
            Task { @MainActor in
                self?.handleWebSocketEvent(event)
            }
        }
        wsConnected = true
    }

    private func disconnectWebSocket() {
        webSocket.disconnect()
        wsConnected = false
    }

    private func handleWebSocketEvent(_ event: AuxRealtimeEvent) {
        switch event {
        case .joined(let payload):
            wsConnected = true
            applyRoomSync(payload)

        case .error(let code):
            wsConnected = false
            toastMessage = code

        case .disconnected:
            wsConnected = false

        case .message(let payload):
            handleRealtimeMessage(payload)
        }
    }

    private func handleRealtimeMessage(_ payload: [String: Any]) {
        guard let type = payload["type"] as? String else { return }

        if type == "aux.player.left", payload["cancelled"] as? Bool == true {
            toastMessage = "Room was cancelled"
            resetSession()
            return
        }

        if type == "aux.bracket.created" {
            scheduleRefresh()
            applyRoomSync(payload)
            return
        }

        if type == "aux.matchup.play_a" || type == "aux.matchup.play_b" {
            applyRoomSync(payload)
            handlePlaybackEvent(payload, side: type == "aux.matchup.play_a" ? "a" : "b")
            return
        }

        if type == "aux.matchup.reveal" || type == "aux.game.finished" {
            snippetPlayer.stop()
            applyRoomSync(payload)
            if let winner = payload["winner"] as? [String: Any],
               let trackName = winner["trackName"] as? String {
                toastMessage = "Winner: \(trackName)"
            }
            return
        }

        if type == "aux.rematch" || type == "aux.rematch.joined" {
            if let newRoomId = payload["newRoomId"] as? String {
                Task {
                    roomState = try? await api.request(Endpoints.auxRoom(roomId: newRoomId), method: .get)
                    if let roomState {
                        connectWebSocket(roomId: roomState.room.id)
                        toastMessage = "Moved to rematch lobby"
                    }
                }
            }
            return
        }

        let applied = applyRoomSync(payload)
        if !applied && (type == "aux.player.joined" || type == "aux.player.left") {
            scheduleRefresh()
        }
    }

    private func handlePlaybackEvent(_ payload: [String: Any], side: String) {
        guard let submissionDict = (payload["submission"] ?? payload[side == "a" ? "submissionA" : "submissionB"]) as? [String: Any],
              let submissionData = try? JSONSerialization.data(withJSONObject: submissionDict),
              let submission = try? JSONDecoder.snakeCase.decode(AuxBattleSubmission.self, from: submissionData) else {
            return
        }

        let countdownEndsAt = payload["countdownEndsAt"] as? String
        let durationMs = payload["snippetDurationMs"] as? Int

        snippetPlayer.playMatchupSnippet(
            submission: submission,
            side: side,
            countdownEndsAt: countdownEndsAt,
            durationMs: durationMs
        )
    }

    @discardableResult
    private func applyRoomSync(_ payload: [String: Any]) -> Bool {
        guard var state = roomState else { return false }
        if let roomId = payload["roomId"] as? String, roomId != state.room.id { return false }

        var changed = false

        if let status = payload["status"] as? String,
           let parsed = AuxRoomStatus(rawValue: status) {
            state = state.updatingRoomStatus(parsed)
            changed = true
        }

        if payload["currentMatchupId"] != nil || payload["currentMatchupId"] is NSNull {
            let matchupId = payload["currentMatchupId"] as? String
            state = state.updatingCurrentMatchupId(matchupId)
            changed = true
        }

        if let players = decodePlayers(from: payload["players"]) {
            state = state.mergingPlayers(players)
            changed = true
        }

        if let meta = decodeMeta(from: payload["meta"]) ?? decodeMeta(from: payload) {
            state = state.updatingMeta(meta)
            changed = true
        }

        if let allLocked = payload["allLocked"] as? Bool {
            state = state.updatingAllSubmitted(allLocked)
            changed = true
        }

        if let allVoted = payload["allVoted"] as? Bool {
            state = state.updatingAllVoted(allVoted)
            changed = true
        }

        if let submissions = decodeSubmissions(from: payload["submissions"]) {
            state = state.updatingSubmissions(submissions)
            changed = true
        }

        if let matchup = decodeMatchup(from: payload["matchup"]) {
            state = state.mergingMatchup(matchup)
            changed = true
        } else if let matchupId = payload["matchupId"] as? String {
            let partial = AuxBattleMatchupPartial.from(payload: payload, matchupId: matchupId)
            state = state.mergingMatchupPartial(partial)
            changed = true
        }

        if typeSpecificSubmissionLocked(payload) {
            state = state.markUserSubmitted(payload["userId"] as? String)
            changed = true
        }

        if changed {
            applyRoomState(state)
        }

        return changed
    }

    private func typeSpecificSubmissionLocked(_ payload: [String: Any]) -> Bool {
        payload["type"] as? String == "aux.submission.locked" && payload["userId"] != nil
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            await self?.refreshRoom()
        }
    }

    private func applyRoomState(_ state: AuxRoomState) {
        roomState = state
    }

    private func auxPOST<T: Decodable>(
        _ endpoint: APIEndpoint,
        body: (any Encodable)? = nil
    ) async throws -> T {
        try await api.request(
            endpoint,
            method: .post,
            body: body,
            preserveBodyKeyNames: true
        )
    }

    private func performRoomAction(_ endpoint: (String) -> APIEndpoint) async -> Bool {
        guard let roomId = roomState?.room.id else { return false }

        isSubmitting = true
        lastError = nil
        defer { isSubmitting = false }

        do {
            let state: AuxRoomState = try await api.request(endpoint(roomId), method: .post)
            applyRoomState(state)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Decoding helpers

    private func decodePlayers(from value: Any?) -> [AuxBattlePlayer]? {
        guard let array = value as? [[String: Any]],
              let data = try? JSONSerialization.data(withJSONObject: array) else { return nil }
        return try? JSONDecoder.snakeCase.decode([AuxBattlePlayer].self, from: data)
    }

    private func decodeSubmissions(from value: Any?) -> [AuxBattleSubmission]? {
        guard let array = value as? [[String: Any]],
              let data = try? JSONSerialization.data(withJSONObject: array) else { return nil }
        return try? JSONDecoder.snakeCase.decode([AuxBattleSubmission].self, from: data)
    }

    private func decodeMatchup(from value: Any?) -> AuxBattleMatchup? {
        guard let dict = value as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder.snakeCase.decode(AuxBattleMatchup.self, from: data)
    }

    private func decodeMeta(from value: Any?) -> AuxBattleMeta? {
        guard let dict = value as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder.snakeCase.decode(AuxBattleMeta.self, from: data)
    }
}

// MARK: - Room state mutations

private struct AuxBattleMatchupPartial {
    let id: String
    let status: AuxMatchupStatus?
    let submissionA: AuxBattleSubmission?
    let submissionB: AuxBattleSubmission?
    let winnerSubmissionId: String?
    let voteCounts: AuxBattleVoteCount?

    static func from(payload: [String: Any], matchupId: String) -> AuxBattleMatchupPartial {
        let decoder = JSONDecoder.snakeCase
        func decodeSubmission(_ key: String) -> AuxBattleSubmission? {
            guard let dict = payload[key] as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? decoder.decode(AuxBattleSubmission.self, from: data)
        }

        let statusRaw = (payload["matchup"] as? [String: Any])?["status"] as? String ?? payload["status"] as? String
        let status = statusRaw.flatMap(AuxMatchupStatus.init(rawValue:))

        var voteCounts: AuxBattleVoteCount?
        if let counts = payload["voteCounts"] as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: counts) {
            voteCounts = try? decoder.decode(AuxBattleVoteCount.self, from: data)
        }

        return AuxBattleMatchupPartial(
            id: matchupId,
            status: status,
            submissionA: decodeSubmission("submissionA"),
            submissionB: decodeSubmission("submissionB"),
            winnerSubmissionId: payload["winnerSubmissionId"] as? String,
            voteCounts: voteCounts
        )
    }
}

private extension AuxRoomState {
    func updatingRoomStatus(_ status: AuxRoomStatus) -> AuxRoomState {
        AuxRoomState(
            room: AuxBattleRoom(
                id: room.id, code: room.code, hostId: room.hostId, prompt: room.prompt,
                maxPlayers: room.maxPlayers, snippetLengthSeconds: room.snippetLengthSeconds,
                songSource: room.songSource, status: status, currentMatchupId: room.currentMatchupId,
                createdAt: room.createdAt, startedAt: room.startedAt, finishedAt: room.finishedAt
            ),
            host: host, players: players, submissions: submissions, bracket: bracket,
            currentMatchup: currentMatchup, playAgain: playAgain, rematch: rematch, meta: meta
        )
    }

    func updatingCurrentMatchupId(_ id: String?) -> AuxRoomState {
        let matchup = id.flatMap { mid in bracket?.matchups.first { $0.id == mid } ?? currentMatchup }
        return AuxRoomState(
            room: AuxBattleRoom(
                id: room.id, code: room.code, hostId: room.hostId, prompt: room.prompt,
                maxPlayers: room.maxPlayers, snippetLengthSeconds: room.snippetLengthSeconds,
                songSource: room.songSource, status: room.status, currentMatchupId: id,
                createdAt: room.createdAt, startedAt: room.startedAt, finishedAt: room.finishedAt
            ),
            host: host, players: players, submissions: submissions, bracket: bracket,
            currentMatchup: matchup, playAgain: playAgain, rematch: rematch, meta: meta
        )
    }

    func mergingPlayers(_ incoming: [AuxBattlePlayer]) -> AuxRoomState {
        var merged = players
        for player in incoming {
            if let index = merged.firstIndex(where: { $0.userId == player.userId }) {
                merged[index] = player
            } else {
                merged.append(player)
            }
        }
        return AuxRoomState(
            room: room, host: host, players: merged, submissions: submissions,
            bracket: bracket, currentMatchup: currentMatchup, playAgain: playAgain,
            rematch: rematch, meta: meta
        )
    }

    func updatingMeta(_ newMeta: AuxBattleMeta) -> AuxRoomState {
        AuxRoomState(
            room: room, host: host, players: players, submissions: submissions,
            bracket: bracket, currentMatchup: currentMatchup, playAgain: playAgain,
            rematch: rematch, meta: newMeta
        )
    }

    func updatingAllSubmitted(_ value: Bool) -> AuxRoomState {
        AuxRoomState(
            room: room, host: host, players: players, submissions: submissions,
            bracket: bracket, currentMatchup: currentMatchup, playAgain: playAgain,
            rematch: rematch,
            meta: AuxBattleMeta(allSubmitted: value, allVoted: meta?.allVoted, playerCount: meta?.playerCount)
        )
    }

    func updatingAllVoted(_ value: Bool) -> AuxRoomState {
        AuxRoomState(
            room: room, host: host, players: players, submissions: submissions,
            bracket: bracket, currentMatchup: currentMatchup, playAgain: playAgain,
            rematch: rematch,
            meta: AuxBattleMeta(allSubmitted: meta?.allSubmitted, allVoted: value, playerCount: meta?.playerCount)
        )
    }

    func updatingSubmissions(_ submissions: [AuxBattleSubmission]) -> AuxRoomState {
        AuxRoomState(
            room: room, host: host, players: players, submissions: submissions,
            bracket: bracket, currentMatchup: currentMatchup, playAgain: playAgain,
            rematch: rematch, meta: meta
        )
    }

    func mergingMatchup(_ partial: AuxBattleMatchup) -> AuxRoomState {
        mergingMatchupPartial(AuxBattleMatchupPartial(
            id: partial.id,
            status: partial.status,
            submissionA: partial.submissionA,
            submissionB: partial.submissionB,
            winnerSubmissionId: partial.winnerSubmissionId,
            voteCounts: partial.voteCounts
        ))
    }

    func mergingMatchupPartial(_ partial: AuxBattleMatchupPartial) -> AuxRoomState {
        var matchups = bracket?.matchups ?? []
        if let index = matchups.firstIndex(where: { $0.id == partial.id }) {
            let existing = matchups[index]
            matchups[index] = AuxBattleMatchup(
                id: partial.id,
                roundNumber: existing.roundNumber,
                matchupNumber: existing.matchupNumber,
                status: partial.status ?? existing.status,
                submissionA: partial.submissionA ?? existing.submissionA,
                submissionB: partial.submissionB ?? existing.submissionB,
                winnerSubmissionId: partial.winnerSubmissionId ?? existing.winnerSubmissionId,
                nextMatchupId: existing.nextMatchupId,
                nextSlot: existing.nextSlot,
                playAStartedAt: existing.playAStartedAt,
                playBStartedAt: existing.playBStartedAt,
                votingStartedAt: existing.votingStartedAt,
                voteCounts: partial.voteCounts ?? existing.voteCounts,
                voters: existing.voters,
                myVote: existing.myVote,
                finishedAt: existing.finishedAt
            )
        }

        let newBracket = AuxBattleBracket(matchups: matchups)
        let current = room.currentMatchupId.flatMap { id in matchups.first { $0.id == id } }

        return AuxRoomState(
            room: room, host: host, players: players, submissions: submissions,
            bracket: newBracket, currentMatchup: current ?? currentMatchup,
            playAgain: playAgain, rematch: rematch, meta: meta
        )
    }

    func markUserSubmitted(_ userId: String?) -> AuxRoomState {
        guard let userId else { return self }
        let updatedPlayers = players.map { player -> AuxBattlePlayer in
            guard player.userId == userId else { return player }
            return AuxBattlePlayer(
                userId: player.userId,
                isHost: player.isHost,
                joinedAt: player.joinedAt,
                profile: player.profile,
                hasSubmitted: true,
                submission: player.submission
            )
        }
        return AuxRoomState(
            room: room, host: host, players: updatedPlayers, submissions: submissions,
            bracket: bracket, currentMatchup: currentMatchup, playAgain: playAgain,
            rematch: rematch, meta: meta
        )
    }
}

private extension JSONDecoder {
    static var snakeCase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
