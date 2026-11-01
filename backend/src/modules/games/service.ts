import { z } from "zod"
import { supabase } from "../../config/supabase.js"
import { generateRandomId } from "../../lib/auth.js"
import { fetchNicheTrackDetail } from "../music/helpers.js"
import { emitToAuxUser } from "./auxSocketManager.js"

export const AUX_ROOM_STATUSES = [
    "lobby",
    "submitting",
    "bracket",
    "matchup_playing",
    "voting",
    "finished",
    "cancelled",
    "error",
] as const

export type AuxRoomStatus = (typeof AUX_ROOM_STATUSES)[number]

export const createRoomSchema = z.object({
    prompt: z.string().trim().min(1).max(200),
    maxPlayers: z.number().int().min(4).max(8).optional(),
    snippetLengthSeconds: z.union([z.literal(5), z.literal(10), z.literal(15), z.literal(20)]).optional(),
    songSource: z.enum(["niche", "apple", "any"]).optional(),
})

export const updateRoomSettingsSchema = createRoomSchema.partial().refine(
    (value) => Object.keys(value).length > 0,
    { message: "At least one setting is required" }
)

export const joinByCodeSchema = z.object({
    code: z.string().trim().min(4).max(8),
})

export const submitSongSchema = z
    .object({
        source: z.enum(["niche", "apple"]),
        trackId: z.string().trim().min(1).optional(),
        nicheTrackId: z.string().trim().min(1).optional(),
        snippetStartMs: z.number().int().min(0).nullable().optional(),
    })
    .superRefine((value, ctx) => {
        if (value.source === "apple" && !value.trackId) {
            ctx.addIssue({ code: "custom", message: "trackId is required for apple tracks" })
        }
        if (value.source === "niche" && !value.nicheTrackId) {
            ctx.addIssue({ code: "custom", message: "nicheTrackId is required for niche tracks" })
        }
    })

export const voteSchema = z.object({
    submissionId: z.string().trim().min(1),
})

const PROFILE_SELECT = "id, username, display_name, avatar_url, is_verified"
const COUNTDOWN_MS = 3000
const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

export class AuxBattleError extends Error {
    code: string
    status: number

    constructor(code: string, message: string, status = 400) {
        super(message)
        this.code = code
        this.status = status
    }
}

type RoomRow = {
    id: string
    code: string
    host_id: string
    prompt: string | null
    max_players: number
    snippet_length_seconds: number
    song_source: string
    status: AuxRoomStatus
    current_matchup_id: string | null
    rematch_from_room_id: string | null
    created_at: string
    started_at: string | null
    finished_at: string | null
}

type PlayerRow = {
    room_id: string
    user_id: string
    is_host: boolean
    joined_at: string | null
    left_at: string | null
}

type SubmissionRow = {
    id: string
    room_id: string
    user_id: string
    source: string
    track_id: string | null
    niche_track_id: string | null
    track_name: string
    artist_name: string
    artwork_url: string | null
    music_url: string | null
    snippet_start_ms: number | null
    snippet_duration_ms: number
    eliminated_at: string | null
    created_at: string
}

type MatchupRow = {
    id: string
    room_id: string
    round_number: number
    matchup_number: number | null
    submission_a_id: string | null
    submission_b_id: string | null
    winner_submission_id: string | null
    next_matchup_id: string | null
    next_slot: string | null
    status: string
    play_a_started_at: string | null
    play_b_started_at: string | null
    voting_started_at: string | null
    voting_ends_at: string | null
    created_at: string
    finished_at: string | null
}

type ProfileRow = {
    id: string
    username: string
    display_name: string | null
    avatar_url: string | null
    is_verified: boolean
}

type ResolvedTrackMeta = {
    trackName: string
    artistName: string
    artworkUrl: string | null
    musicUrl: string | null
}

type SubmissionPayload = {
    id: string
    userId: string
    source: string
    trackId: string | null
    nicheTrackId: string | null
    trackName: string
    artistName: string
    artworkUrl: string | null
    musicUrl: string | null
    snippetStartMs: number | null
    snippetDurationMs: number
    eliminatedAt: string | null
    createdAt: string
    profile: ProfileRow | null
}

function profileDisplayName(profile: { display_name?: string | null; username?: string | null } | null | undefined) {
    if (!profile) return null
    return profile.display_name || profile.username || null
}

function nicheArtistName(track: Record<string, unknown>): string {
    const owner = track.owner as { display_name?: string | null; username?: string | null } | undefined
    const fromOwner = profileDisplayName(owner)
    if (fromOwner) return fromOwner
    return primaryArtistNameFromCredits(track.credits)
}

function primaryArtistNameFromCredits(credits: unknown): string {
    if (!Array.isArray(credits) || credits.length === 0) return "Unknown Artist"

    const sorted = [...credits].sort(
        (a, b) => Number(!!b?.is_primary) - Number(!!a?.is_primary)
    )
    const artist = sorted[0]?.artist
    if (artist && typeof artist === "object") {
        return profileDisplayName(artist as { display_name?: string | null; username?: string | null }) || "Unknown Artist"
    }

    return "Unknown Artist"
}

async function resolveTrackMetadata(
    source: "niche" | "apple",
    trackId: string | null,
    nicheTrackId: string | null,
    viewerUserId: string
): Promise<ResolvedTrackMeta> {
    if (source === "niche") {
        if (!nicheTrackId) {
            throw new AuxBattleError("TRACK_REQUIRED", "nicheTrackId is required for niche tracks", 400)
        }

        const detail = await fetchNicheTrackDetail(nicheTrackId, viewerUserId)
        if (!detail?.track) {
            throw new AuxBattleError("TRACK_NOT_FOUND", "Track not found", 404)
        }

        const track = detail.track as Record<string, unknown>
        return {
            trackName: String(track.name ?? "Unknown"),
            artistName: nicheArtistName(track),
            artworkUrl: typeof track.artwork_url === "string" ? track.artwork_url : null,
            musicUrl: typeof track.music_url === "string" ? track.music_url : null,
        }
    }

    if (!trackId) {
        throw new AuxBattleError("TRACK_REQUIRED", "trackId is required for apple tracks", 400)
    }

    const { data: track, error } = await supabase
        .schema("public")
        .from("tracks")
        .select("id, name, artwork_url, preview_url, artist_id")
        .eq("id", trackId)
        .maybeSingle()

    if (error || !track) {
        throw new AuxBattleError("TRACK_NOT_FOUND", "Track not found", 404)
    }

    let artistName = "Unknown Artist"
    if (track.artist_id) {
        const { data: artist } = await supabase
            .schema("public")
            .from("artists")
            .select("name")
            .eq("id", track.artist_id)
            .maybeSingle()
        if (artist?.name) artistName = artist.name
    }

    return {
        trackName: track.name ?? "Unknown",
        artistName,
        artworkUrl: track.artwork_url,
        musicUrl: track.preview_url,
    }
}

async function ensureSubmissionMetadata(
    row: SubmissionRow,
    viewerUserId: string,
    persist = false
): Promise<SubmissionRow> {
    const needsMeta =
        !row.track_name ||
        !row.artist_name ||
        row.artist_name === "Unknown Artist" ||
        !row.music_url ||
        !row.artwork_url

    if (!needsMeta) return row

    const meta = await resolveTrackMetadata(
        row.source as "niche" | "apple",
        row.track_id,
        row.niche_track_id,
        viewerUserId
    )

    const enriched: SubmissionRow = {
        ...row,
        track_name: meta.trackName,
        artist_name: meta.artistName,
        artwork_url: meta.artworkUrl,
        music_url: meta.musicUrl,
    }

    if (persist) {
        await supabase
            .schema("public")
            .from("aux_battle_submissions")
            .update({
                track_name: meta.trackName,
                artist_name: meta.artistName,
                artwork_url: meta.artworkUrl,
                music_url: meta.musicUrl,
            })
            .eq("id", row.id)
    }

    return enriched
}

function toSubmissionPayload(
    row: SubmissionRow,
    profile: ProfileRow | undefined,
    visible = true
): SubmissionPayload | { userId: string; lockedIn: true } {
    if (!visible) {
        return {
            userId: row.user_id,
            lockedIn: true,
        }
    }

    return {
        id: row.id,
        userId: row.user_id,
        source: row.source,
        trackId: row.track_id,
        nicheTrackId: row.niche_track_id,
        trackName: row.track_name,
        artistName: row.artist_name,
        artworkUrl: row.artwork_url,
        musicUrl: row.music_url,
        snippetStartMs: row.snippet_start_ms,
        snippetDurationMs: row.snippet_duration_ms,
        eliminatedAt: row.eliminated_at,
        createdAt: row.created_at,
        profile: profile ?? null,
    }
}

async function loadSubmissionPayloadById(
    roomId: string,
    submissionId: string
): Promise<SubmissionPayload | null> {
    const { data, error } = await supabase
        .schema("public")
        .from("aux_battle_submissions")
        .select("*")
        .eq("room_id", roomId)
        .eq("id", submissionId)
        .maybeSingle()

    if (error || !data) return null

    const row = await ensureSubmissionMetadata(data as SubmissionRow, data.user_id, true)
    const profiles = await loadProfiles([row.user_id])
    const payload = toSubmissionPayload(row, profiles.get(row.user_id), true)
    return "lockedIn" in payload ? null : payload
}

async function loadMatchupSubmissionPayloads(roomId: string, matchup: MatchupRow) {
    const [submissionA, submissionB] = await Promise.all([
        matchup.submission_a_id
            ? loadSubmissionPayloadById(roomId, matchup.submission_a_id)
            : Promise.resolve(null),
        matchup.submission_b_id
            ? loadSubmissionPayloadById(roomId, matchup.submission_b_id)
            : Promise.resolve(null),
    ])

    return { submissionA, submissionB }
}

async function loadRoomSubmissionPayloads(roomId: string): Promise<SubmissionPayload[]> {
    const { data, error } = await supabase
        .schema("public")
        .from("aux_battle_submissions")
        .select("*")
        .eq("room_id", roomId)
        .order("created_at", { ascending: true })

    if (error || !data?.length) return []

    const rows = await Promise.all(
        (data as SubmissionRow[]).map((row) => ensureSubmissionMetadata(row, row.user_id, true))
    )
    const profiles = await loadProfiles(rows.map((row) => row.user_id))

    return rows
        .map((row) => toSubmissionPayload(row, profiles.get(row.user_id), true))
        .filter((row): row is SubmissionPayload => !("lockedIn" in row))
}

function shuffle<T>(items: T[]): T[] {
    const copy = [...items]
    for (let i = copy.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1))
        const tmp = copy[i]!
        copy[i] = copy[j]!
        copy[j] = tmp
    }
    return copy
}

function generateRoomCode(): string {
    let code = ""
    for (let i = 0; i < 6; i++) {
        code += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)]
    }
    return code
}

async function generateUniqueRoomCode(): Promise<string> {
    for (let attempt = 0; attempt < 12; attempt++) {
        const code = generateRoomCode()
        const { data } = await supabase
            .schema("public")
            .from("aux_battle_rooms")
            .select("id")
            .eq("code", code)
            .maybeSingle()
        if (!data) return code
    }
    throw new AuxBattleError("CODE_GENERATION_FAILED", "Could not generate room code", 500)
}

async function loadRoom(roomId: string): Promise<RoomRow> {
    const { data, error } = await supabase
        .schema("public")
        .from("aux_battle_rooms")
        .select("*")
        .eq("id", roomId)
        .maybeSingle()

    if (error) throw new AuxBattleError("ROOM_LOAD_FAILED", error.message, 500)
    if (!data) throw new AuxBattleError("ROOM_NOT_FOUND", "Room not found", 404)
    return data as RoomRow
}

async function loadActivePlayers(roomId: string): Promise<PlayerRow[]> {
    const { data, error } = await supabase
        .schema("public")
        .from("aux_battle_players")
        .select("*")
        .eq("room_id", roomId)
        .is("left_at", null)
        .order("joined_at", { ascending: true })

    if (error) throw new AuxBattleError("PLAYERS_LOAD_FAILED", error.message, 500)
    return (data ?? []) as PlayerRow[]
}

export async function buildPlayersSyncPayload(roomId: string) {
    const room = await loadRoom(roomId)
    const players = await loadActivePlayers(roomId)
    const profiles = await loadProfiles(players.map((p) => p.user_id))

    const { data: submissions } = await supabase
        .schema("public")
        .from("aux_battle_submissions")
        .select("user_id")
        .eq("room_id", roomId)

    const submitted = new Set((submissions ?? []).map((row) => row.user_id as string))

    return {
        roomId: room.id,
        status: room.status,
        playerCount: players.length,
        meta: {
            playerCount: players.length,
            allSubmitted:
                players.length > 0 && players.every((player) => submitted.has(player.user_id)),
        },
        players: players.map((player) => ({
            userId: player.user_id,
            isHost: player.is_host,
            joinedAt: player.joined_at,
            profile: profiles.get(player.user_id) ?? null,
            hasSubmitted: submitted.has(player.user_id),
            submission: null,
        })),
    }
}

export async function assertActivePlayer(roomId: string, userId: string) {
    const { data, error } = await supabase
        .schema("public")
        .from("aux_battle_players")
        .select("user_id")
        .eq("room_id", roomId)
        .eq("user_id", userId)
        .is("left_at", null)
        .maybeSingle()

    if (error) throw new AuxBattleError("PLAYER_CHECK_FAILED", error.message, 500)
    if (!data) throw new AuxBattleError("NOT_IN_ROOM", "You are not in this room", 403)
}

async function assertHost(room: RoomRow, userId: string) {
    if (room.host_id !== userId) {
        throw new AuxBattleError("NOT_HOST", "Only the host can do this", 403)
    }
}

function isDuplicateSongError(error: { code?: string; message?: string; details?: string }) {
    if (error.code !== "23505") return false
    const msg = `${error.message ?? ""} ${error.details ?? ""}`.toLowerCase()
    return (
        msg.includes("unique_apple_track") ||
        msg.includes("unique_niche_track") ||
        msg.includes("aux_battle_submissions_unique")
    )
}

function assertStatus(room: RoomRow, allowed: AuxRoomStatus[]) {
    if (!allowed.includes(room.status)) {
        throw new AuxBattleError("INVALID_ROOM_STATUS", `Room is in ${room.status}`, 409)
    }
}

async function loadProfiles(userIds: string[]): Promise<Map<string, ProfileRow>> {
    if (userIds.length === 0) return new Map()

    const { data, error } = await supabase
        .schema("public")
        .from("profiles")
        .select(PROFILE_SELECT)
        .in("id", userIds)

    if (error) throw new AuxBattleError("PROFILES_LOAD_FAILED", error.message, 500)

    const map = new Map<string, ProfileRow>()
    for (const profile of (data ?? []) as ProfileRow[]) {
        map.set(profile.id, profile)
    }
    return map
}

export async function getRoomState(roomId: string, viewerUserId: string) {
    await assertActivePlayer(roomId, viewerUserId)

    const room = await loadRoom(roomId)
    const players = await loadActivePlayers(roomId)
    const playerIds = players.map((p) => p.user_id)
    const profiles = await loadProfiles(playerIds)

    const { data: submissionsRaw, error: submissionsError } = await supabase
        .schema("public")
        .from("aux_battle_submissions")
        .select("*")
        .eq("room_id", roomId)
        .order("created_at", { ascending: true })

    if (submissionsError) {
        throw new AuxBattleError("SUBMISSIONS_LOAD_FAILED", submissionsError.message, 500)
    }

    const submissions = await Promise.all(
        ((submissionsRaw ?? []) as SubmissionRow[]).map((row) =>
            ensureSubmissionMetadata(row, viewerUserId, true)
        )
    )
    const submissionByUser = new Map(submissions.map((s) => [s.user_id, s]))
    const submissionById = new Map(submissions.map((s) => [s.id, s]))

    const showAllSubmissions = room.status !== "lobby" && room.status !== "submitting"

    const formattedPlayers = players.map((player) => {
        const submission = submissionByUser.get(player.user_id)
        return {
            userId: player.user_id,
            isHost: player.is_host,
            joinedAt: player.joined_at,
            profile: profiles.get(player.user_id) ?? null,
            hasSubmitted: !!submission,
            submission:
                submission && (player.user_id === viewerUserId || showAllSubmissions)
                    ? toSubmissionPayload(submission, profiles.get(player.user_id), true)
                    : submission
                      ? toSubmissionPayload(submission, profiles.get(player.user_id), false)
                      : null,
        }
    })

    const { data: matchupsRaw, error: matchupsError } = await supabase
        .schema("public")
        .from("aux_battle_matchups")
        .select("*")
        .eq("room_id", roomId)
        .order("round_number", { ascending: true })
        .order("matchup_number", { ascending: true })

    if (matchupsError) {
        throw new AuxBattleError("MATCHUPS_LOAD_FAILED", matchupsError.message, 500)
    }

    const matchups = (matchupsRaw ?? []) as MatchupRow[]
    const matchupIds = matchups.map((m) => m.id)

    let votesByMatchup = new Map<string, { submissionId: string; userId: string }[]>()
    let myVotesByMatchup = new Map<string, string>()

    if (matchupIds.length > 0) {
        const { data: votesRaw, error: votesError } = await supabase
            .schema("public")
            .from("aux_battle_votes")
            .select("matchup_id, submission_id, user_id")
            .in("matchup_id", matchupIds)

        if (votesError) {
            throw new AuxBattleError("VOTES_LOAD_FAILED", votesError.message, 500)
        }

        for (const vote of votesRaw ?? []) {
            const list = votesByMatchup.get(vote.matchup_id) ?? []
            list.push({ submissionId: vote.submission_id, userId: vote.user_id })
            votesByMatchup.set(vote.matchup_id, list)
            if (vote.user_id === viewerUserId) {
                myVotesByMatchup.set(vote.matchup_id, vote.submission_id)
            }
        }
    }

    const formattedMatchups = matchups.map((matchup) => {
        const subA = matchup.submission_a_id ? submissionById.get(matchup.submission_a_id) : undefined
        const subB = matchup.submission_b_id ? submissionById.get(matchup.submission_b_id) : undefined
        const votes = votesByMatchup.get(matchup.id) ?? []

        const voteCounts = {
            a: votes.filter((v) => v.submissionId === matchup.submission_a_id).length,
            b: votes.filter((v) => v.submissionId === matchup.submission_b_id).length,
        }

        const voters = votes.map((v) => ({
            userId: v.userId,
            submissionId: v.submissionId,
            profile: profiles.get(v.userId) ?? null,
        }))

        return {
            id: matchup.id,
            roundNumber: matchup.round_number,
            matchupNumber: matchup.matchup_number,
            status: matchup.status,
            submissionA: subA
                ? toSubmissionPayload(subA, profiles.get(subA.user_id), true)
                : null,
            submissionB: subB
                ? toSubmissionPayload(subB, profiles.get(subB.user_id), true)
                : null,
            winnerSubmissionId: matchup.winner_submission_id,
            nextMatchupId: matchup.next_matchup_id,
            nextSlot: matchup.next_slot,
            playAStartedAt: matchup.play_a_started_at,
            playBStartedAt: matchup.play_b_started_at,
            votingStartedAt: matchup.voting_started_at,
            voteCounts,
            voters,
            myVote: myVotesByMatchup.get(matchup.id) ?? null,
            finishedAt: matchup.finished_at,
        }
    })

    const currentMatchup = room.current_matchup_id
        ? formattedMatchups.find((m) => m.id === room.current_matchup_id) ?? null
        : null

    const { data: playAgainRaw, error: playAgainError } = await supabase
        .schema("public")
        .from("aux_battle_play_again")
        .select("user_id, created_at")
        .eq("room_id", roomId)
        .order("created_at", { ascending: true })

    if (playAgainError) {
        throw new AuxBattleError("PLAY_AGAIN_LOAD_FAILED", playAgainError.message, 500)
    }

    const playAgainUserIds = (playAgainRaw ?? []).map((row) => row.user_id)
    const rematchRoom = room.status === "finished" ? await findRematchRoom(room) : null

    const allSubmitted =
        players.length > 0 && players.every((player) => submissionByUser.has(player.user_id))

    const activeMatchupVotes = room.current_matchup_id
        ? votesByMatchup.get(room.current_matchup_id) ?? []
        : []
    const allVoted =
        players.length > 0 &&
        activeMatchupVotes.length >= players.length

    return {
        room: {
            id: room.id,
            code: room.code,
            hostId: room.host_id,
            prompt: room.prompt,
            maxPlayers: room.max_players,
            snippetLengthSeconds: room.snippet_length_seconds,
            songSource: room.song_source,
            status: room.status,
            currentMatchupId: room.current_matchup_id,
            createdAt: room.created_at,
            startedAt: room.started_at,
            finishedAt: room.finished_at,
        },
        host: profiles.get(room.host_id) ?? null,
        players: formattedPlayers,
        submissions: showAllSubmissions
            ? submissions
                  .map((s) => toSubmissionPayload(s, profiles.get(s.user_id), true))
                  .filter((s) => !("lockedIn" in s))
            : submissions
                  .filter((s) => s.user_id === viewerUserId)
                  .map((s) => toSubmissionPayload(s, profiles.get(s.user_id), true))
                  .filter((s) => !("lockedIn" in s)),
        bracket: {
            matchups: formattedMatchups,
        },
        currentMatchup,
        playAgain: {
            userIds: playAgainUserIds,
            myPlayAgain: playAgainUserIds.includes(viewerUserId),
            count: playAgainUserIds.length,
        },
        rematch: rematchRoom
            ? {
                  roomId: rematchRoom.id,
                  code: rematchRoom.code,
              }
            : null,
        meta: {
            allSubmitted,
            allVoted,
            playerCount: players.length,
        },
    }
}

async function findRematchRoom(room: RoomRow): Promise<RoomRow | null> {
    const { data, error } = await supabase
        .schema("public")
        .from("aux_battle_rooms")
        .select("*")
        .eq("rematch_from_room_id", room.id)
        .maybeSingle()

    if (error) throw new AuxBattleError("REMATCH_LOOKUP_FAILED", error.message, 500)
    return (data as RoomRow | null) ?? null
}

async function broadcast(roomId: string, event: Record<string, unknown>) {
    const players = await loadActivePlayers(roomId)
    const payload = { roomId, ...event }
    for (const player of players) {
        emitToAuxUser(player.user_id, payload)
    }
}

async function broadcastRoomSync(roomId: string, event: Record<string, unknown>) {
    try {
        const room = await loadRoom(roomId)
        const sync = await buildPlayersSyncPayload(roomId)
        await broadcast(roomId, {
            ...event,
            ...sync,
            currentMatchupId: room.current_matchup_id,
        })
    } catch {
        await broadcast(roomId, event)
    }
}

export async function createAuxRoom(
    hostId: string,
    input: z.infer<typeof createRoomSchema>
) {
    const roomId = generateRandomId(16)
    const code = await generateUniqueRoomCode()

    const { data: room, error: roomError } = await supabase
        .schema("public")
        .from("aux_battle_rooms")
        .insert({
            id: roomId,
            code,
            host_id: hostId,
            prompt: input.prompt,
            max_players: input.maxPlayers ?? 8,
            snippet_length_seconds: input.snippetLengthSeconds ?? 15,
            song_source: input.songSource ?? "any",
            status: "lobby",
        })
        .select("*")
        .single()

    if (roomError) {
        throw new AuxBattleError("ROOM_CREATE_FAILED", roomError.message, 400)
    }

    const { error: playerError } = await supabase
        .schema("public")
        .from("aux_battle_players")
        .insert({
            room_id: roomId,
            user_id: hostId,
            is_host: true,
        })

    if (playerError) {
        throw new AuxBattleError("HOST_JOIN_FAILED", playerError.message, 400)
    }

    return getRoomState(roomId, hostId)
}

async function joinRoomInternal(room: RoomRow, userId: string) {
    if (room.status !== "lobby") {
        throw new AuxBattleError("ROOM_NOT_JOINABLE", "Game already started", 409)
    }

    const players = await loadActivePlayers(room.id)
    if (players.length >= room.max_players) {
        throw new AuxBattleError("ROOM_FULL", "Room is full", 409)
    }

    const existing = players.find((p) => p.user_id === userId)
    if (existing) {
        return getRoomState(room.id, userId)
    }

    const { error } = await supabase
        .schema("public")
        .from("aux_battle_players")
        .insert({
            room_id: room.id,
            user_id: userId,
            is_host: false,
        })

    if (error) {
        // rejoin if they left before
        const { data: prior } = await supabase
            .schema("public")
            .from("aux_battle_players")
            .select("*")
            .eq("room_id", room.id)
            .eq("user_id", userId)
            .maybeSingle()

        if (prior?.left_at) {
            const { error: rejoinError } = await supabase
                .schema("public")
                .from("aux_battle_players")
                .update({ left_at: null, joined_at: new Date().toISOString() })
                .eq("room_id", room.id)
                .eq("user_id", userId)

            if (rejoinError) {
                throw new AuxBattleError("REJOIN_FAILED", rejoinError.message, 400)
            }

            const sync = await buildPlayersSyncPayload(room.id)
            await broadcast(room.id, {
                type: "aux.player.joined",
                userId,
                ...sync,
            })
        } else {
            throw new AuxBattleError("JOIN_FAILED", error.message, 400)
        }
    }

    const sync = await buildPlayersSyncPayload(room.id)
    await broadcast(room.id, {
        type: "aux.player.joined",
        userId,
        ...sync,
    })

    return getRoomState(room.id, userId)
}

export async function joinAuxRoomByCode(userId: string, code: string) {
    const normalized = code.trim().toUpperCase()

    const { data: room, error } = await supabase
        .schema("public")
        .from("aux_battle_rooms")
        .select("*")
        .eq("code", normalized)
        .maybeSingle()

    if (error) throw new AuxBattleError("ROOM_LOOKUP_FAILED", error.message, 500)
    if (!room) throw new AuxBattleError("ROOM_NOT_FOUND", "Invalid room code", 404)

    return joinRoomInternal(room as RoomRow, userId)
}

export async function joinAuxRoomById(userId: string, roomId: string) {
    const room = await loadRoom(roomId)
    return joinRoomInternal(room, userId)
}

export async function leaveAuxRoom(userId: string, roomId: string) {
    await assertActivePlayer(roomId, userId)
    const room = await loadRoom(roomId)

    const { error } = await supabase
        .schema("public")
        .from("aux_battle_players")
        .update({ left_at: new Date().toISOString() })
        .eq("room_id", roomId)
        .eq("user_id", userId)

    if (error) throw new AuxBattleError("LEAVE_FAILED", error.message, 400)

    if (room.host_id === userId && room.status === "lobby") {
        await supabase
            .schema("public")
            .from("aux_battle_rooms")
            .update({ status: "cancelled" })
            .eq("id", roomId)
    }

    const sync = await buildPlayersSyncPayload(roomId)
    await broadcast(roomId, {
        type: "aux.player.left",
        userId,
        cancelled: room.host_id === userId && room.status === "lobby",
        ...sync,
    })

    return { left: true }
}

export async function updateAuxRoomSettings(
    hostId: string,
    roomId: string,
    input: z.infer<typeof updateRoomSettingsSchema>
) {
    const room = await loadRoom(roomId)
    await assertHost(room, hostId)
    assertStatus(room, ["lobby"])

    const patch: Record<string, unknown> = {}

    if (input.prompt !== undefined) patch.prompt = input.prompt
    if (input.maxPlayers !== undefined) {
        const players = await loadActivePlayers(roomId)
        if (input.maxPlayers < players.length) {
            throw new AuxBattleError(
                "ROOM_TOO_SMALL",
                "maxPlayers cannot be less than the current player count",
                409
            )
        }
        patch.max_players = input.maxPlayers
    }
    if (input.snippetLengthSeconds !== undefined) {
        patch.snippet_length_seconds = input.snippetLengthSeconds
    }
    if (input.songSource !== undefined) patch.song_source = input.songSource

    const { error } = await supabase
        .schema("public")
        .from("aux_battle_rooms")
        .update(patch)
        .eq("id", roomId)

    if (error) throw new AuxBattleError("SETTINGS_UPDATE_FAILED", error.message, 400)

    const sync = await buildPlayersSyncPayload(roomId)
    await broadcast(roomId, {
        type: "aux.status",
        ...sync,
    })

    return getRoomState(roomId, hostId)
}

export async function startSubmissions(hostId: string, roomId: string) {
    const room = await loadRoom(roomId)
    await assertHost(room, hostId)
    assertStatus(room, ["lobby"])

    const players = await loadActivePlayers(roomId)
    if (players.length < 2) {
        throw new AuxBattleError("NOT_ENOUGH_PLAYERS", "Need at least 2 players", 409)
    }

    const { error } = await supabase
        .schema("public")
        .from("aux_battle_rooms")
        .update({
            status: "submitting",
            started_at: new Date().toISOString(),
        })
        .eq("id", roomId)

    if (error) throw new AuxBattleError("START_FAILED", error.message, 400)

    await broadcastRoomSync(roomId, {
        type: "aux.status",
        status: "submitting",
    })

    return getRoomState(roomId, hostId)
}

async function validateSongSource(room: RoomRow, source: "niche" | "apple") {
    if (room.song_source === "any") return
    if (room.song_source !== source) {
        throw new AuxBattleError("INVALID_SONG_SOURCE", `Room only allows ${room.song_source} tracks`, 400)
    }
}

export async function submitSong(
    userId: string,
    roomId: string,
    input: z.infer<typeof submitSongSchema>
) {
    const room = await loadRoom(roomId)
    await assertActivePlayer(roomId, userId)
    assertStatus(room, ["submitting"])

    await validateSongSource(room, input.source)

    const snippetDurationMs = room.snippet_length_seconds * 1000
    const trackId = input.source === "apple" ? input.trackId! : null
    const nicheTrackId = input.source === "niche" ? input.nicheTrackId! : null

    const meta = await resolveTrackMetadata(input.source, trackId, nicheTrackId, userId)

    const submissionId = generateRandomId(16)
    const row = {
        id: submissionId,
        room_id: roomId,
        user_id: userId,
        source: input.source,
        track_id: trackId,
        niche_track_id: nicheTrackId,
        track_name: meta.trackName,
        artist_name: meta.artistName,
        artwork_url: meta.artworkUrl,
        music_url: meta.musicUrl,
        snippet_start_ms: input.snippetStartMs ?? null,
        snippet_duration_ms: snippetDurationMs,
    }

    const { error } = await supabase
        .schema("public")
        .from("aux_battle_submissions")
        .upsert(row, { onConflict: "room_id,user_id" })

    if (error) {
        if (isDuplicateSongError(error)) {
            throw new AuxBattleError("SONG_NOT_AVAILABLE", "That song isn't available", 409)
        }
        throw new AuxBattleError("SUBMIT_FAILED", error.message, 400)
    }

    const players = await loadActivePlayers(roomId)
    const { count } = await supabase
        .schema("public")
        .from("aux_battle_submissions")
        .select("id", { count: "exact", head: true })
        .eq("room_id", roomId)

    const allLocked = (count ?? 0) >= players.length

    await broadcastRoomSync(roomId, {
        type: "aux.submission.locked",
        userId,
        allLocked,
    })

    return getRoomState(roomId, userId)
}

type BracketMatchupInsert = {
    id: string
    room_id: string
    round_number: number
    matchup_number: number
    submission_a_id: string | null
    submission_b_id: string | null
    next_matchup_id: string | null
    next_slot: "a" | "b" | null
    status: string
    winner_submission_id?: string | null
    finished_at?: string | null
}

function bracketSizeFor(count: number): number {
    let size = 2
    while (size < count) size *= 2
    return Math.min(size, 8)
}

function buildBracketMatchups(roomId: string, submissionIds: string[]): BracketMatchupInsert[] {
    const shuffled = shuffle(submissionIds)
    const n = shuffled.length
    const size = bracketSizeFor(n)
    const rounds = Math.log2(size)
    const idsByRound: string[][] = []

    for (let round = 1; round <= rounds; round++) {
        const count = size / Math.pow(2, round)
        idsByRound[round - 1] = Array.from({ length: count }, () => generateRandomId(16))
    }

    const matchups: BracketMatchupInsert[] = []

    for (let round = 1; round <= rounds; round++) {
        const roundIds = idsByRound[round - 1]!
        const roundMatchupCount = roundIds.length
        for (let i = 0; i < roundMatchupCount; i++) {
            const id = roundIds[i]!
            let nextMatchupId: string | null = null
            let nextSlot: "a" | "b" | null = null

            if (round < rounds) {
                const parentIdx = Math.floor(i / 2)
                nextMatchupId = idsByRound[round]![parentIdx]!
                nextSlot = i % 2 === 0 ? "a" : "b"
            }

            matchups.push({
                id,
                room_id: roomId,
                round_number: round,
                matchup_number: i + 1,
                submission_a_id: null,
                submission_b_id: null,
                next_matchup_id: nextMatchupId,
                next_slot: nextSlot,
                status: "pending",
            })
        }
    }

    const slots: (string | null)[] = Array(size).fill(null)
    for (let i = 0; i < n; i++) {
        slots[i] = shuffled[i]!
    }

    const roundOne = matchups.filter((m) => m.round_number === 1)
    for (let i = 0; i < roundOne.length; i++) {
        const matchup = roundOne[i]!
        matchup.submission_a_id = slots[i * 2] ?? null
        matchup.submission_b_id = slots[i * 2 + 1] ?? null
    }

    return matchups
}

async function resolveByeMatchups(roomId: string, matchups: BracketMatchupInsert[]) {
    const byId = new Map(matchups.map((m) => [m.id, m]))
    let changed = true

    while (changed) {
        changed = false
        for (const matchup of matchups) {
            if (matchup.status !== "pending") continue

            const hasA = !!matchup.submission_a_id
            const hasB = !!matchup.submission_b_id
            if (hasA === hasB) continue

            const winnerId = hasA ? matchup.submission_a_id! : matchup.submission_b_id!
            matchup.status = "finished"
            matchup.winner_submission_id = winnerId
            matchup.finished_at = new Date().toISOString()
            changed = true

            if (matchup.next_matchup_id && matchup.next_slot) {
                const parent = byId.get(matchup.next_matchup_id)
                if (parent) {
                    if (matchup.next_slot === "a") parent.submission_a_id = winnerId
                    else parent.submission_b_id = winnerId
                }
            }

            await supabase
                .schema("public")
                .from("aux_battle_matchups")
                .update({
                    status: "finished",
                    winner_submission_id: winnerId,
                    finished_at: matchup.finished_at,
                })
                .eq("id", matchup.id)

            if (matchup.next_matchup_id && matchup.next_slot) {
                const parent = byId.get(matchup.next_matchup_id)!
                await supabase
                    .schema("public")
                    .from("aux_battle_matchups")
                    .update({
                        submission_a_id: parent.submission_a_id,
                        submission_b_id: parent.submission_b_id,
                    })
                    .eq("id", parent.id)
            }
        }
    }
}

export async function createBracket(hostId: string, roomId: string) {
    const room = await loadRoom(roomId)
    await assertHost(room, hostId)
    assertStatus(room, ["submitting"])

    const players = await loadActivePlayers(roomId)
    if (players.length < 2) {
        throw new AuxBattleError("NOT_ENOUGH_PLAYERS", "Need at least 2 players", 409)
    }

    const { data: submissions, error: submissionsError } = await supabase
        .schema("public")
        .from("aux_battle_submissions")
        .select("id, user_id")
        .eq("room_id", roomId)

    if (submissionsError) {
        throw new AuxBattleError("SUBMISSIONS_LOAD_FAILED", submissionsError.message, 500)
    }

    if ((submissions ?? []).length < players.length) {
        throw new AuxBattleError("NOT_ALL_SUBMITTED", "Wait for everyone to lock in", 409)
    }

    const existing = await supabase
        .schema("public")
        .from("aux_battle_matchups")
        .select("id")
        .eq("room_id", roomId)
        .limit(1)

    if ((existing.data ?? []).length > 0) {
        throw new AuxBattleError("BRACKET_EXISTS", "Bracket already created", 409)
    }

    const submissionIds = (submissions ?? []).map((s) => s.id as string)
    const bracketMatchups = buildBracketMatchups(roomId, submissionIds)

    const { error: insertError } = await supabase
        .schema("public")
        .from("aux_battle_matchups")
        .insert(bracketMatchups)

    if (insertError) {
        throw new AuxBattleError("BRACKET_CREATE_FAILED", insertError.message, 400)
    }

    await resolveByeMatchups(roomId, bracketMatchups)

    const { error: roomError } = await supabase
        .schema("public")
        .from("aux_battle_rooms")
        .update({ status: "bracket", current_matchup_id: null })
        .eq("id", roomId)

    if (roomError) throw new AuxBattleError("ROOM_UPDATE_FAILED", roomError.message, 400)

    const submissionPayloads = await loadRoomSubmissionPayloads(roomId)

    await broadcastRoomSync(roomId, {
        type: "aux.bracket.created",
        status: "bracket",
        submissions: submissionPayloads,
    })

    return getRoomState(roomId, hostId)
}

async function findNextPendingMatchup(roomId: string): Promise<MatchupRow | null> {
    const { data, error } = await supabase
        .schema("public")
        .from("aux_battle_matchups")
        .select("*")
        .eq("room_id", roomId)
        .eq("status", "pending")
        .order("round_number", { ascending: true })
        .order("matchup_number", { ascending: true })

    if (error) throw new AuxBattleError("MATCHUP_LOOKUP_FAILED", error.message, 500)

    for (const matchup of (data ?? []) as MatchupRow[]) {
        if (matchup.submission_a_id && matchup.submission_b_id) {
            return matchup
        }
    }

    return null
}

export async function startBracket(hostId: string, roomId: string) {
    const room = await loadRoom(roomId)
    await assertHost(room, hostId)
    assertStatus(room, ["bracket"])

    const nextMatchup = await findNextPendingMatchup(roomId)
    if (!nextMatchup) {
        throw new AuxBattleError("NO_PENDING_MATCHUP", "No matchups ready to start", 409)
    }

    const { error } = await supabase
        .schema("public")
        .from("aux_battle_rooms")
        .update({ current_matchup_id: nextMatchup.id })
        .eq("id", roomId)

    if (error) throw new AuxBattleError("ROOM_UPDATE_FAILED", error.message, 400)

    const matchup = await loadMatchup(roomId, nextMatchup.id)
    const { submissionA, submissionB } = await loadMatchupSubmissionPayloads(roomId, matchup)

    await broadcastRoomSync(roomId, {
        type: "aux.status",
        status: "bracket",
        currentMatchupId: nextMatchup.id,
        matchup: {
            id: matchup.id,
            status: matchup.status,
            submissionA,
            submissionB,
        },
    })

    return getRoomState(roomId, hostId)
}

async function loadMatchup(roomId: string, matchupId: string): Promise<MatchupRow> {
    const { data, error } = await supabase
        .schema("public")
        .from("aux_battle_matchups")
        .select("*")
        .eq("id", matchupId)
        .eq("room_id", roomId)
        .maybeSingle()

    if (error) throw new AuxBattleError("MATCHUP_LOAD_FAILED", error.message, 500)
    if (!data) throw new AuxBattleError("MATCHUP_NOT_FOUND", "Matchup not found", 404)
    return data as MatchupRow
}

export async function startMatchupA(hostId: string, roomId: string, matchupId: string) {
    const room = await loadRoom(roomId)
    await assertHost(room, hostId)
    assertStatus(room, ["bracket", "matchup_playing"])

    const matchup = await loadMatchup(roomId, matchupId)
    if (matchup.status !== "pending") {
        throw new AuxBattleError("MATCHUP_NOT_PENDING", "Matchup already started", 409)
    }
    if (!matchup.submission_a_id || !matchup.submission_b_id) {
        throw new AuxBattleError("MATCHUP_NOT_READY", "Matchup is missing a submission", 409)
    }

    const now = new Date()
    const countdownEndsAt = new Date(now.getTime() + COUNTDOWN_MS).toISOString()

    const { error: matchupError } = await supabase
        .schema("public")
        .from("aux_battle_matchups")
        .update({
            status: "playing_a",
            play_a_started_at: now.toISOString(),
        })
        .eq("id", matchupId)

    if (matchupError) throw new AuxBattleError("MATCHUP_UPDATE_FAILED", matchupError.message, 400)

    const { error: roomError } = await supabase
        .schema("public")
        .from("aux_battle_rooms")
        .update({
            status: "matchup_playing",
            current_matchup_id: matchupId,
        })
        .eq("id", roomId)

    if (roomError) throw new AuxBattleError("ROOM_UPDATE_FAILED", roomError.message, 400)

    const { submissionA, submissionB } = await loadMatchupSubmissionPayloads(roomId, matchup)

    await broadcastRoomSync(roomId, {
        type: "aux.matchup.play_a",
        status: "matchup_playing",
        matchupId,
        countdownEndsAt,
        snippetDurationMs: room.snippet_length_seconds * 1000,
        side: "a",
        matchup: {
            id: matchup.id,
            status: "playing_a",
            submissionA,
            submissionB,
        },
        submission: submissionA,
        submissionA,
        submissionB,
    })

    return getRoomState(roomId, hostId)
}

export async function startMatchupB(hostId: string, roomId: string, matchupId: string) {
    const room = await loadRoom(roomId)
    await assertHost(room, hostId)
    assertStatus(room, ["matchup_playing"])

    const matchup = await loadMatchup(roomId, matchupId)
    if (matchup.status !== "playing_a") {
        throw new AuxBattleError("INVALID_MATCHUP_STATE", "Play side A first", 409)
    }

    const now = new Date()
    const countdownEndsAt = new Date(now.getTime() + COUNTDOWN_MS).toISOString()

    const { error } = await supabase
        .schema("public")
        .from("aux_battle_matchups")
        .update({
            status: "playing_b",
            play_b_started_at: now.toISOString(),
        })
        .eq("id", matchupId)

    if (error) throw new AuxBattleError("MATCHUP_UPDATE_FAILED", error.message, 400)

    const { submissionA, submissionB } = await loadMatchupSubmissionPayloads(roomId, matchup)

    await broadcastRoomSync(roomId, {
        type: "aux.matchup.play_b",
        status: "matchup_playing",
        matchupId,
        countdownEndsAt,
        snippetDurationMs: room.snippet_length_seconds * 1000,
        side: "b",
        matchup: {
            id: matchup.id,
            status: "playing_b",
            submissionA,
            submissionB,
        },
        submission: submissionB,
        submissionA,
        submissionB,
    })

    return getRoomState(roomId, hostId)
}

export async function startVoting(hostId: string, roomId: string, matchupId: string) {
    const room = await loadRoom(roomId)
    await assertHost(room, hostId)
    assertStatus(room, ["matchup_playing"])

    const matchup = await loadMatchup(roomId, matchupId)
    if (matchup.status !== "playing_b") {
        throw new AuxBattleError("INVALID_MATCHUP_STATE", "Play both songs first", 409)
    }

    const now = new Date().toISOString()

    const { error: matchupError } = await supabase
        .schema("public")
        .from("aux_battle_matchups")
        .update({
            status: "voting",
            voting_started_at: now,
        })
        .eq("id", matchupId)

    if (matchupError) throw new AuxBattleError("MATCHUP_UPDATE_FAILED", matchupError.message, 400)

    const { error: roomError } = await supabase
        .schema("public")
        .from("aux_battle_rooms")
        .update({ status: "voting" })
        .eq("id", roomId)

    if (roomError) throw new AuxBattleError("ROOM_UPDATE_FAILED", roomError.message, 400)

    const { submissionA, submissionB } = await loadMatchupSubmissionPayloads(roomId, matchup)

    await broadcastRoomSync(roomId, {
        type: "aux.matchup.voting",
        status: "voting",
        matchupId,
        matchup: {
            id: matchup.id,
            status: "voting",
            submissionA,
            submissionB,
        },
        submissionA,
        submissionB,
    })

    return getRoomState(roomId, hostId)
}

export async function castVote(
    userId: string,
    roomId: string,
    matchupId: string,
    submissionId: string
) {
    const room = await loadRoom(roomId)
    await assertActivePlayer(roomId, userId)
    assertStatus(room, ["voting"])

    if (room.current_matchup_id !== matchupId) {
        throw new AuxBattleError("WRONG_MATCHUP", "This matchup is not active", 409)
    }

    const matchup = await loadMatchup(roomId, matchupId)
    if (matchup.status !== "voting") {
        throw new AuxBattleError("NOT_VOTING", "Voting is not open", 409)
    }

    if (submissionId !== matchup.submission_a_id && submissionId !== matchup.submission_b_id) {
        throw new AuxBattleError("INVALID_VOTE", "Pick one of the two songs", 400)
    }

    const { error } = await supabase
        .schema("public")
        .from("aux_battle_votes")
        .upsert(
            {
                matchup_id: matchupId,
                user_id: userId,
                submission_id: submissionId,
            },
            { onConflict: "matchup_id,user_id" }
        )

    if (error) throw new AuxBattleError("VOTE_FAILED", error.message, 400)

    const players = await loadActivePlayers(roomId)
    const { count } = await supabase
        .schema("public")
        .from("aux_battle_votes")
        .select("user_id", { count: "exact", head: true })
        .eq("matchup_id", matchupId)

    const allVoted = (count ?? 0) >= players.length

    await broadcastRoomSync(roomId, {
        type: "aux.vote.cast",
        matchupId,
        userId,
        allVoted,
    })

    return getRoomState(roomId, userId)
}

async function countVotes(matchup: MatchupRow) {
    const { data, error } = await supabase
        .schema("public")
        .from("aux_battle_votes")
        .select("submission_id")
        .eq("matchup_id", matchup.id)

    if (error) throw new AuxBattleError("VOTES_LOAD_FAILED", error.message, 500)

    const votes = data ?? []
    return {
        a: votes.filter((v) => v.submission_id === matchup.submission_a_id).length,
        b: votes.filter((v) => v.submission_id === matchup.submission_b_id).length,
    }
}

function pickWinner(matchup: MatchupRow, voteCounts: { a: number; b: number }): string {
    if (voteCounts.a > voteCounts.b) return matchup.submission_a_id!
    if (voteCounts.b > voteCounts.a) return matchup.submission_b_id!

    // tie — random winner
    return Math.random() < 0.5 ? matchup.submission_a_id! : matchup.submission_b_id!
}

async function advanceWinner(matchup: MatchupRow, winnerSubmissionId: string) {
    if (!matchup.next_matchup_id || !matchup.next_slot) return

    const patch =
        matchup.next_slot === "a"
            ? { submission_a_id: winnerSubmissionId }
            : { submission_b_id: winnerSubmissionId }

    const { error } = await supabase
        .schema("public")
        .from("aux_battle_matchups")
        .update(patch)
        .eq("id", matchup.next_matchup_id)

    if (error) throw new AuxBattleError("ADVANCE_FAILED", error.message, 400)
}

export async function revealMatchup(hostId: string, roomId: string, matchupId: string) {
    const room = await loadRoom(roomId)
    await assertHost(room, hostId)
    assertStatus(room, ["voting"])

    const matchup = await loadMatchup(roomId, matchupId)
    if (matchup.status !== "voting") {
        throw new AuxBattleError("NOT_VOTING", "Start voting first", 409)
    }

    const voteCounts = await countVotes(matchup)
    const winnerSubmissionId = pickWinner(matchup, voteCounts)
    const loserSubmissionId =
        winnerSubmissionId === matchup.submission_a_id
            ? matchup.submission_b_id
            : matchup.submission_a_id

    const now = new Date().toISOString()

    const { error: matchupError } = await supabase
        .schema("public")
        .from("aux_battle_matchups")
        .update({
            status: "finished",
            winner_submission_id: winnerSubmissionId,
            finished_at: now,
        })
        .eq("id", matchupId)

    if (matchupError) throw new AuxBattleError("MATCHUP_UPDATE_FAILED", matchupError.message, 400)

    if (loserSubmissionId) {
        await supabase
            .schema("public")
            .from("aux_battle_submissions")
            .update({ eliminated_at: now })
            .eq("id", loserSubmissionId)
    }

    await advanceWinner(matchup, winnerSubmissionId)

    const isFinal = !matchup.next_matchup_id
    let newStatus: AuxRoomStatus = "bracket"

    if (isFinal) {
        newStatus = "finished"
        await supabase
            .schema("public")
            .from("aux_battle_rooms")
            .update({
                status: "finished",
                finished_at: now,
                current_matchup_id: null,
            })
            .eq("id", roomId)
    } else {
        await supabase
            .schema("public")
            .from("aux_battle_rooms")
            .update({
                status: "bracket",
                current_matchup_id: null,
            })
            .eq("id", roomId)
    }

    const [winner, loser] = await Promise.all([
        loadSubmissionPayloadById(roomId, winnerSubmissionId),
        loserSubmissionId
            ? loadSubmissionPayloadById(roomId, loserSubmissionId)
            : Promise.resolve(null),
    ])

    await broadcastRoomSync(roomId, {
        type: "aux.matchup.reveal",
        matchupId,
        winnerSubmissionId,
        loserSubmissionId,
        winner,
        loser,
        voteCounts,
        isFinal,
        status: newStatus,
    })

    if (isFinal) {
        await broadcastRoomSync(roomId, {
            type: "aux.game.finished",
            winnerSubmissionId,
            winner,
            status: "finished",
        })
    }

    return getRoomState(roomId, hostId)
}

export async function markPlayAgain(userId: string, roomId: string) {
    const room = await loadRoom(roomId)
    await assertActivePlayer(roomId, userId)
    assertStatus(room, ["finished"])

    const existingRematch = await findRematchRoom(room)
    if (existingRematch) {
        await joinRoomInternal(existingRematch, userId)
        await broadcast(roomId, {
            type: "aux.rematch.joined",
            oldRoomId: roomId,
            newRoomId: existingRematch.id,
            userId,
        })
        return getRoomState(existingRematch.id, userId)
    }

    const { error } = await supabase
        .schema("public")
        .from("aux_battle_play_again")
        .upsert(
            {
                room_id: roomId,
                user_id: userId,
            },
            { onConflict: "room_id,user_id" }
        )

    if (error) throw new AuxBattleError("PLAY_AGAIN_FAILED", error.message, 400)

    const { count } = await supabase
        .schema("public")
        .from("aux_battle_play_again")
        .select("user_id", { count: "exact", head: true })
        .eq("room_id", roomId)

    await broadcastRoomSync(roomId, {
        type: "aux.play_again",
        userId,
        count: count ?? 0,
    })

    return getRoomState(roomId, userId)
}

export async function createRematch(hostId: string, roomId: string) {
    const room = await loadRoom(roomId)
    await assertHost(room, hostId)
    assertStatus(room, ["finished"])

    const existingRematch = await findRematchRoom(room)
    if (existingRematch) {
        return {
            room: await getRoomState(existingRematch.id, hostId),
            alreadyCreated: true,
        }
    }

    const { data: playAgainRows, error: playAgainError } = await supabase
        .schema("public")
        .from("aux_battle_play_again")
        .select("user_id")
        .eq("room_id", roomId)

    if (playAgainError) {
        throw new AuxBattleError("PLAY_AGAIN_LOAD_FAILED", playAgainError.message, 500)
    }

    const participantIds = new Set<string>([hostId])
    for (const row of playAgainRows ?? []) {
        participantIds.add(row.user_id as string)
    }

    const newRoomId = generateRandomId(16)
    const code = await generateUniqueRoomCode()

    const { error: roomError } = await supabase
        .schema("public")
        .from("aux_battle_rooms")
        .insert({
            id: newRoomId,
            code,
            host_id: hostId,
            prompt: room.prompt,
            max_players: room.max_players,
            snippet_length_seconds: room.snippet_length_seconds,
            song_source: room.song_source,
            status: "lobby",
            rematch_from_room_id: roomId,
        })

    if (roomError) throw new AuxBattleError("REMATCH_CREATE_FAILED", roomError.message, 400)

    const playerRows = [...participantIds].map((userId) => ({
        room_id: newRoomId,
        user_id: userId,
        is_host: userId === hostId,
    }))

    const { error: playersError } = await supabase
        .schema("public")
        .from("aux_battle_players")
        .insert(playerRows)

    if (playersError) throw new AuxBattleError("REMATCH_PLAYERS_FAILED", playersError.message, 400)

    await broadcast(roomId, {
        type: "aux.rematch",
        oldRoomId: roomId,
        newRoomId,
        code,
    })

    return {
        room: await getRoomState(newRoomId, hostId),
        alreadyCreated: false,
    }
}
