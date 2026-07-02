import { supabase } from "../../config/supabase.js"
import { generateRandomId } from "../../lib/auth.js"

const DAY_MS = 24 * 60 * 60 * 1000
const RECENT_MATCH_DAYS = 14
const PAIR_COOLDOWN_DAYS = 90
const CANDIDATE_LIMIT = 40
const MIN_SCORE = 40
const REASON_SAMPLE_LIMIT = 3

export type MatchTrackSample = {
    id: string
    name: string
    artwork_url: string | null
    source: string | null
    artist_name: string | null
}

export type MatchMutualSample = {
    id: string
    username: string
    display_name: string | null
    avatar_url: string | null
}

export type MatchGenreSample = {
    id: string
    name: string
    slug: string
}

export type MatchReason = {
    sharedAppleTracks: number
    sharedNicheTracks: number
    sharedNichePlays: number
    sharedFeedEvents: number
    sharedGenres: number
    mutuals: number
    topReasons: string[]
    sharedAppleTrackSamples?: MatchTrackSample[]
    sharedNicheTrackSamples?: MatchTrackSample[]
    sharedNichePlayTrackSamples?: MatchTrackSample[]
    sharedFeedTrackSamples?: MatchTrackSample[]
    sharedGenreSamples?: MatchGenreSample[]
    mutualSamples?: MatchMutualSample[]
}

export const SCORE_WEIGHTS = {
    nichePlay: 41,
    nicheTrack: 20,
    appleTrack: 13,
    feedEvent: 7,
    genre: 4,
    mutual: 3,
    mutualFollowBonus: 4,
} as const

export type TasteProfile = {
    apple: Set<string>
    niche: Set<string>
    plays: Set<string>
    feed: Set<string>
    genres: Set<string>
    friends: Set<string>
    following: Set<string>
}

export type PairCounts = {
    sharedAppleTracks: number
    sharedNicheTracks: number
    sharedNichePlays: number
    sharedFeedEvents: number
    sharedGenres: number
    mutualFriends: number
    mutualFollow: number
    mutuals: number
    score: number
}

export function computePairScore(
    tasteA: TasteProfile,
    tasteB: TasteProfile,
    userA: string,
    userB: string
): PairCounts {
    const sharedAppleTracks = intersectCount(tasteA.apple, tasteB.apple)
    const sharedNicheTracks = intersectCount(tasteA.niche, tasteB.niche)
    const sharedNichePlays = intersectCount(tasteA.plays, tasteB.plays)
    const sharedFeedEvents = intersectCount(tasteA.feed, tasteB.feed)
    const sharedGenres = intersectCount(tasteA.genres, tasteB.genres)

    let mutualFriends = 0
    for (const id of tasteA.friends) {
        if (tasteB.friends.has(id)) mutualFriends++
    }

    const aFollowsB = tasteA.following.has(userB)
    const bFollowsA = tasteB.following.has(userA)
    const mutualFollow = aFollowsB && bFollowsA ? 1 : 0
    const mutuals = mutualFriends + mutualFollow

    const score = Math.min(
        100,
        sharedNichePlays * SCORE_WEIGHTS.nichePlay +
            sharedNicheTracks * SCORE_WEIGHTS.nicheTrack +
            sharedAppleTracks * SCORE_WEIGHTS.appleTrack +
            sharedFeedEvents * SCORE_WEIGHTS.feedEvent +
            sharedGenres * SCORE_WEIGHTS.genre +
            mutuals * SCORE_WEIGHTS.mutual +
            (mutualFollow ? SCORE_WEIGHTS.mutualFollowBonus : 0)
    )

    return {
        sharedAppleTracks,
        sharedNicheTracks,
        sharedNichePlays,
        sharedFeedEvents,
        sharedGenres,
        mutualFriends,
        mutualFollow,
        mutuals,
        score,
    }
}

export type PairScoreResult = {
    score: number
    reason: MatchReason
}

export type MatchStrength = "good" | "strong" | "insane"

export type MatchActions = {
    primary: string
    secondary: string
}

export type MatchOtherUser = {
    username: string
    display_name: string | null
}

export type MatchCheckPayload = {
    id: string
    strength: MatchStrength
    headline: string
    subtitle: string
    actions: MatchActions
    otherUser: unknown
    reason_json: MatchReason
    expires_at: string
    status: string
    viewer_has_responded: boolean
    other_has_responded: boolean
    declined_by_user_id: string | null
}

const ACTION_SETS = [
    // normal
    { primary: "Say hi", secondary: "Maybe later" },
    { primary: "Start chat", secondary: "Not now" },
    { primary: "Message them", secondary: "Skip" },
    { primary: "Open DM", secondary: "Close" },

    // music themed
    { primary: "Pass the aux", secondary: "Skip track" },
    { primary: "Start the duet", secondary: "Not my tempo" },
    { primary: "Queue the convo", secondary: "Leave the queue" },
    { primary: "Follow the sound", secondary: "Pause this" },

    // funny
    { primary: "Do it for the plot", secondary: "Abort mission" },
    { primary: "Shoot the shot", secondary: "I fear intimacy" },
    { primary: "Enter the lore", secondary: "Too much lore" },
    { primary: "Trust the algorithm", secondary: "My aux is private" },

    // corny
    { primary: "Meet your music twin", secondary: "Maybe another song" },
    { primary: "Find your harmony", secondary: "Different rhythm" },
    { primary: "Let the music speak", secondary: "Let it fade" },

    // overly romantic
    { primary: "Accept destiny", secondary: "Deny fate" },
    { primary: "Begin the love song", secondary: "End the soundtrack" },
    { primary: "Answer the universe", secondary: "Let the stars wait" },
    { primary: "Start the first verse", secondary: "Silence the chorus" },

    // emoji
    { primary: "Say hi 👋", secondary: "Maybe later 🕰️" },
    { primary: "Start chat 🎵", secondary: "Skip ⏭️" },
    { primary: "Send a vibe 🎧", secondary: "Not now 👋" },
] as const

function daysAgoIso(days: number) {
    return new Date(Date.now() - days * DAY_MS).toISOString()
}

function uniqueStrings(values: Array<string | null | undefined>) {
    return [...new Set(values.filter((v): v is string => Boolean(v)))]
}

function intersectCount(a: Set<string>, b: Set<string>) {
    let count = 0
    for (const id of a) {
        if (b.has(id)) count++
    }
    return count
}

export function intersectIds(a: Set<string>, b: Set<string>, limit = REASON_SAMPLE_LIMIT) {
    const out: string[] = []
    for (const id of a) {
        if (b.has(id)) {
            out.push(id)
            if (out.length >= limit) break
        }
    }
    return out
}

export function mutualFriendIds(friendsA: Set<string>, friendsB: Set<string>, limit = REASON_SAMPLE_LIMIT) {
    const out: string[] = []
    for (const id of friendsA) {
        if (friendsB.has(id)) {
            out.push(id)
            if (out.length >= limit) break
        }
    }
    return out
}

export async function fetchAppleTrackSamples(trackIds: string[]): Promise<MatchTrackSample[]> {
    if (trackIds.length === 0) return []
    const { data, error } = await supabase
        .schema("public")
        .from("tracks")
        .select("id, name, artwork_url, source, artists(name)")
        .in("id", trackIds)
    if (error) throw new Error(error.message)

    const byId = new Map<string, MatchTrackSample>()
    for (const row of data ?? []) {
        const artist = row.artists as { name: string } | { name: string }[] | null
        const artistName = Array.isArray(artist) ? artist[0]?.name ?? null : artist?.name ?? null
        byId.set(row.id, {
            id: row.id,
            name: row.name,
            artwork_url: row.artwork_url,
            source: row.source,
            artist_name: artistName,
        })
    }
    return trackIds.flatMap((id) => {
        const row = byId.get(id)
        return row ? [row] : []
    })
}

export async function fetchNicheTrackSamples(trackIds: string[]): Promise<MatchTrackSample[]> {
    if (trackIds.length === 0) return []
    const { data, error } = await supabase
        .schema("public")
        .from("niche_tracks")
        .select("id, name, artwork_url, owner:profiles!niche_tracks_owner_id_fkey(username, display_name)")
        .in("id", trackIds)
    if (error) throw new Error(error.message)

    const byId = new Map<string, MatchTrackSample>()
    for (const row of data ?? []) {
        const owner = row.owner as { username: string; display_name: string | null } | { username: string; display_name: string | null }[] | null
        const ownerRow = Array.isArray(owner) ? owner[0] : owner
        const artistName = ownerRow?.display_name ?? ownerRow?.username ?? null
        byId.set(row.id, {
            id: row.id,
            name: row.name,
            artwork_url: row.artwork_url,
            source: "niche",
            artist_name: artistName,
        })
    }
    return trackIds.flatMap((id) => {
        const row = byId.get(id)
        return row ? [row] : []
    })
}

export async function fetchGenreSamples(genreIds: string[]): Promise<MatchGenreSample[]> {
    if (genreIds.length === 0) return []
    const { data, error } = await supabase
        .schema("public")
        .from("genres")
        .select("id, name, slug")
        .in("id", genreIds)
    if (error) throw new Error(error.message)

    const byId = new Map<string, MatchGenreSample>()
    for (const row of data ?? []) {
        byId.set(row.id, { id: row.id, name: row.name, slug: row.slug })
    }
    return genreIds.flatMap((id) => {
        const row = byId.get(id)
        return row ? [row] : []
    })
}

export async function fetchMutualSamples(userIds: string[]): Promise<MatchMutualSample[]> {
    if (userIds.length === 0) return []
    const { data, error } = await supabase
        .schema("public")
        .from("profiles")
        .select("id, username, display_name, avatar_url")
        .in("id", userIds)
    if (error) throw new Error(error.message)

    const byId = new Map<string, MatchMutualSample>()
    for (const row of data ?? []) {
        byId.set(row.id, row as MatchMutualSample)
    }
    return userIds.flatMap((id) => {
        const row = byId.get(id)
        return row ? [row] : []
    })
}

function orderedPair(userA: string, userB: string): [string, string] {
    return userA < userB ? [userA, userB] : [userB, userA]
}

function quoteName(name: string) {
    return `"${name}"`
}

function otherUserLabel(profile: MatchOtherUser) {
    const display = profile.display_name?.trim()
    return display && display.length > 0 ? display : profile.username
}

export function getMatchStrength(score: number): MatchStrength {
    if (score >= 90) return "insane"
    if (score >= 70) return "strong"
    return "good"
}

export function buildTopReasons(reason: MatchReason): string[] {
    const out: string[] = []
    const play = reason.sharedNichePlayTrackSamples?.[0]
    if (reason.sharedNichePlays > 0) {
        out.push(play ? `You both listened to ${quoteName(play.name)}` : "You both listened to the same Niche tracks")
    }
    const apple = reason.sharedAppleTrackSamples?.[0]
    if (reason.sharedAppleTracks > 0) {
        out.push(apple ? `You both saved ${quoteName(apple.name)}` : "You both saved similar tracks")
    }
    const niche = reason.sharedNicheTrackSamples?.[0]
    if (reason.sharedNicheTracks > 0) {
        out.push(niche ? `You both like ${quoteName(niche.name)}` : "You both like similar Niche tracks")
    }
    const feed = reason.sharedFeedTrackSamples?.[0]
    if (reason.sharedFeedEvents > 0) {
        out.push(
            feed
                ? `You've both been listening to ${quoteName(feed.name)}`
                : "You've been listening to the same tracks"
        )
    }
    const genre = reason.sharedGenreSamples?.[0]
    if (reason.sharedGenres > 0) {
        out.push(
            genre
                ? `You both listen to ${quoteName(genre.name)}`
                : `You share ${reason.sharedGenres} genre${reason.sharedGenres === 1 ? "" : "s"}`
        )
    }
    if (reason.mutuals > 0) {
        out.push(`You have ${reason.mutuals} mutual${reason.mutuals === 1 ? "" : "s"}`)
    }
    return out
}

function formatSharedGenresPhrase(samples: MatchGenreSample[]) {
    const first = samples[0]
    if (!first) return null
    if (samples.length === 1) return `both listen to ${quoteName(first.name)}`
    const second = samples[1]
    if (samples.length === 2 && second) {
        return `both listen to ${quoteName(first.name)} and ${quoteName(second.name)}`
    }
    return `both listen to ${quoteName(first.name)} and ${samples.length - 1} other genres`
}

function formatSharedTracksPhrase(samples: MatchTrackSample[], verb: "saved" | "liked" | "listened to") {
    const first = samples[0]
    if (!first) return null
    if (samples.length === 1) return `both ${verb} ${quoteName(first.name)}`
    const second = samples[1]
    if (samples.length === 2 && second) {
        return `both ${verb} ${quoteName(first.name)} and ${quoteName(second.name)}`
    }
    return `both ${verb} ${quoteName(first.name)} and ${samples.length - 1} other tracks`
}

export function buildMatchSubtitle(otherUser: MatchOtherUser, reason: MatchReason) {
    const name = otherUserLabel(otherUser)
    const clauses: string[] = []

    const playPhrase = formatSharedTracksPhrase(reason.sharedNichePlayTrackSamples ?? [], "listened to")
    const applePhrase = formatSharedTracksPhrase(reason.sharedAppleTrackSamples ?? [], "saved")
    const nichePhrase = formatSharedTracksPhrase(reason.sharedNicheTrackSamples ?? [], "liked")
    const feedPhrase = formatSharedTracksPhrase(reason.sharedFeedTrackSamples ?? [], "listened to")
    const genrePhrase = formatSharedGenresPhrase(reason.sharedGenreSamples ?? [])

    if (playPhrase) clauses.push(playPhrase)
    else if (applePhrase) clauses.push(applePhrase)
    else if (nichePhrase) clauses.push(nichePhrase)
    else if (feedPhrase) clauses.push(feedPhrase)
    else if (genrePhrase) clauses.push(genrePhrase)

    if (genrePhrase && clauses.length > 0 && clauses[0] !== genrePhrase) {
        clauses.push(genrePhrase)
    }

    if (reason.mutuals > 0) {
        clauses.push(`have ${reason.mutuals} mutual${reason.mutuals === 1 ? "" : "s"}`)
    }

    if (clauses.length === 0) {
        return `You and ${name} have similar taste in music.`
    }

    return `You and ${name} ${clauses.join(" and ")}.`
}

export function parseMatchReason(raw: Record<string, unknown>): MatchReason {
    const reason: MatchReason = {
        sharedAppleTracks: Number(raw.sharedAppleTracks ?? 0),
        sharedNicheTracks: Number(raw.sharedNicheTracks ?? 0),
        sharedNichePlays: Number(raw.sharedNichePlays ?? 0),
        sharedFeedEvents: Number(raw.sharedFeedEvents ?? 0),
        sharedGenres: Number(raw.sharedGenres ?? 0),
        mutuals: Number(raw.mutuals ?? 0),
        topReasons: Array.isArray(raw.topReasons)
            ? raw.topReasons.filter((v): v is string => typeof v === "string")
            : [],
    }
    if (Array.isArray(raw.sharedAppleTrackSamples)) {
        reason.sharedAppleTrackSamples = raw.sharedAppleTrackSamples as MatchTrackSample[]
    }
    if (Array.isArray(raw.sharedNicheTrackSamples)) {
        reason.sharedNicheTrackSamples = raw.sharedNicheTrackSamples as MatchTrackSample[]
    }
    if (Array.isArray(raw.sharedNichePlayTrackSamples)) {
        reason.sharedNichePlayTrackSamples = raw.sharedNichePlayTrackSamples as MatchTrackSample[]
    }
    if (Array.isArray(raw.sharedFeedTrackSamples)) {
        reason.sharedFeedTrackSamples = raw.sharedFeedTrackSamples as MatchTrackSample[]
    }
    if (Array.isArray(raw.sharedGenreSamples)) {
        reason.sharedGenreSamples = raw.sharedGenreSamples as MatchGenreSample[]
    }
    if (Array.isArray(raw.mutualSamples)) {
        reason.mutualSamples = raw.mutualSamples as MatchMutualSample[]
    }
    reason.topReasons = buildTopReasons(reason)
    return reason
}

export function buildMatchCheckPayload(params: {
    id: string
    score: number
    reason_json: Record<string, unknown>
    expires_at: string
    status: string
    otherUser: unknown
    viewerHasResponded: boolean
    otherHasResponded: boolean
    declinedByUserId: string | null
}): MatchCheckPayload {
    const reason = parseMatchReason(params.reason_json)
    const otherUser = params.otherUser as MatchOtherUser

    const actionSet =
        ACTION_SETS[Math.floor(Math.random() * ACTION_SETS.length)] ??
        { primary: "Say hi", secondary: "Maybe later" }


    return {
        id: params.id,
        strength: getMatchStrength(params.score),
        headline: "Your music taste matched",
        subtitle: buildMatchSubtitle(otherUser, reason),
        actions: {
            primary: actionSet.primary,
            secondary: actionSet.secondary,
        },
        otherUser: params.otherUser,
        reason_json: reason,
        expires_at: params.expires_at,
        status: params.status,
        viewer_has_responded: params.viewerHasResponded,
        other_has_responded: params.otherHasResponded,
        declined_by_user_id: params.declinedByUserId,
    }
}

async function fetchTrackSets(userId: string) {
    const [likesRes, savesRes] = await Promise.all([
        supabase.schema("public").from("track_likes").select("track_id").eq("user_id", userId).limit(300),
        supabase.schema("public").from("track_saves").select("track_id").eq("user_id", userId).limit(300),
    ])
    if (likesRes.error) throw new Error(likesRes.error.message)
    if (savesRes.error) throw new Error(savesRes.error.message)
    return new Set(uniqueStrings([
        ...(likesRes.data ?? []).map((r) => r.track_id),
        ...(savesRes.data ?? []).map((r) => r.track_id),
    ]))
}

async function fetchNicheTrackSets(userId: string) {
    const [likesRes, savesRes] = await Promise.all([
        supabase.schema("public").from("niche_track_likes").select("track_id").eq("liker_id", userId).limit(300),
        supabase.schema("public").from("niche_track_saves").select("track_id").eq("saver_id", userId).limit(300),
    ])
    if (likesRes.error) throw new Error(likesRes.error.message)
    if (savesRes.error) throw new Error(savesRes.error.message)
    return new Set(uniqueStrings([
        ...(likesRes.data ?? []).map((r) => r.track_id),
        ...(savesRes.data ?? []).map((r) => r.track_id),
    ]))
}

async function fetchNichePlayTrackSet(userId: string) {
    const { data, error } = await supabase
        .schema("public")
        .from("niche_track_play_events")
        .select("track_id")
        .eq("user_id", userId)
        .limit(400)
    if (error) throw new Error(error.message)
    return new Set(uniqueStrings((data ?? []).map((r) => r.track_id)))
}

async function fetchGenreIdsForTracks(playTracks: Set<string>, nicheTracks: Set<string>) {
    const trackIds = uniqueStrings([...playTracks, ...nicheTracks]).slice(0, 200)
    if (trackIds.length === 0) return new Set<string>()

    const { data, error } = await supabase
        .schema("public")
        .from("niche_track_genres")
        .select("genre_id")
        .in("track_id", trackIds)
        .limit(500)
    if (error) throw new Error(error.message)
    return new Set(uniqueStrings((data ?? []).map((r) => r.genre_id)))
}

async function fetchFeedTrackSet(userId: string) {
    const { data, error } = await supabase
        .schema("public")
        .from("feed_events")
        .select("entity_id")
        .eq("user_id", userId)
        .eq("entity_type", "track")
        .limit(400)
    if (error) throw new Error(error.message)
    return new Set(uniqueStrings((data ?? []).map((r) => r.entity_id)))
}

async function fetchFriendIds(userId: string) {
    const { data, error } = await supabase
        .schema("public")
        .from("friends")
        .select("user_a_id, user_b_id")
        .or(`user_a_id.eq.${userId},user_b_id.eq.${userId}`)
    if (error) throw new Error(error.message)
    return new Set(
        (data ?? []).map((r) => (r.user_a_id === userId ? r.user_b_id : r.user_a_id))
    )
}

async function followsUser(followerId: string, followingId: string) {
    const { data, error } = await supabase
        .schema("public")
        .from("follows")
        .select("follower_id")
        .eq("follower_id", followerId)
        .eq("following_id", followingId)
        .maybeSingle()
    if (error) throw new Error(error.message)
    return !!data
}

export async function getActiveUsers(): Promise<string[]> {
    const [profiles, trackLikes, trackSaves, nicheLikes, nicheSaves, nichePlays, feedEvents] = await Promise.all([
        supabase.schema("public").from("profiles").select("id"),
        supabase.schema("public").from("track_likes").select("user_id"),
        supabase.schema("public").from("track_saves").select("user_id"),
        supabase.schema("public").from("niche_track_likes").select("liker_id"),
        supabase.schema("public").from("niche_track_saves").select("saver_id"),
        supabase.schema("public").from("niche_track_play_events").select("user_id"),
        supabase.schema("public").from("feed_events").select("user_id"),
    ])

    for (const res of [profiles, trackLikes, trackSaves, nicheLikes, nicheSaves, nichePlays, feedEvents]) {
        if (res.error) throw new Error(res.error.message)
    }

    return uniqueStrings([
        ...(profiles.data ?? []).map((r) => r.id),
        ...(trackLikes.data ?? []).map((r) => r.user_id),
        ...(trackSaves.data ?? []).map((r) => r.user_id),
        ...(nicheLikes.data ?? []).map((r) => r.liker_id),
        ...(nicheSaves.data ?? []).map((r) => r.saver_id),
        ...(nichePlays.data ?? []).map((r) => r.user_id),
        ...(feedEvents.data ?? []).map((r) => r.user_id),
    ])
}

export async function hasRecentMatch(userId: string): Promise<boolean> {
    const since = daysAgoIso(RECENT_MATCH_DAYS)
    const { data, error } = await supabase
        .schema("public")
        .from("music_matches")
        .select("id")
        .or(`user_a_id.eq.${userId},user_b_id.eq.${userId}`)
        .gte("created_at", since)
        .limit(1)
    if (error) throw new Error(error.message)
    return (data ?? []).length > 0
}

export async function pairMatchedRecently(userA: string, userB: string): Promise<boolean> {
    const [low, high] = orderedPair(userA, userB)
    const since = daysAgoIso(PAIR_COOLDOWN_DAYS)
    const { data, error } = await supabase
        .schema("public")
        .from("music_matches")
        .select("id")
        .eq("user_a_id", low)
        .eq("user_b_id", high)
        .gte("created_at", since)
        .limit(1)
    if (error) throw new Error(error.message)
    return (data ?? []).length > 0
}

export async function scoreUserPair(userA: string, userB: string): Promise<PairScoreResult> {
    const [
        appleA,
        appleB,
        nicheA,
        nicheB,
        nichePlayA,
        nichePlayB,
        feedA,
        feedB,
        friendsA,
        friendsB,
        aFollowsB,
        bFollowsA,
    ] = await Promise.all([
        fetchTrackSets(userA),
        fetchTrackSets(userB),
        fetchNicheTrackSets(userA),
        fetchNicheTrackSets(userB),
        fetchNichePlayTrackSet(userA),
        fetchNichePlayTrackSet(userB),
        fetchFeedTrackSet(userA),
        fetchFeedTrackSet(userB),
        fetchFriendIds(userA),
        fetchFriendIds(userB),
        followsUser(userA, userB),
        followsUser(userB, userA),
    ])

    const [genresA, genresB] = await Promise.all([
        fetchGenreIdsForTracks(nichePlayA, nicheA),
        fetchGenreIdsForTracks(nichePlayB, nicheB),
    ])

    const sharedAppleTracks = intersectCount(appleA, appleB)
    const sharedNicheTracks = intersectCount(nicheA, nicheB)
    const sharedNichePlays = intersectCount(nichePlayA, nichePlayB)
    const sharedFeedEvents = intersectCount(feedA, feedB)
    const sharedGenres = intersectCount(genresA, genresB)

    let mutualFriends = 0
    for (const id of friendsA) {
        if (friendsB.has(id)) mutualFriends++
    }

    const mutualFollow = aFollowsB && bFollowsA ? 1 : 0
    const mutuals = mutualFriends + mutualFollow

    const score = Math.min(
        100,
        sharedNichePlays * SCORE_WEIGHTS.nichePlay +
        sharedNicheTracks * SCORE_WEIGHTS.nicheTrack +
        sharedAppleTracks * SCORE_WEIGHTS.appleTrack +
        sharedFeedEvents * SCORE_WEIGHTS.feedEvent +
        sharedGenres * SCORE_WEIGHTS.genre +
        mutuals * SCORE_WEIGHTS.mutual +
        (mutualFollow ? SCORE_WEIGHTS.mutualFollowBonus : 0)
    )

    const [
        sharedAppleTrackSamples,
        sharedNicheTrackSamples,
        sharedNichePlayTrackSamples,
        sharedFeedTrackSamples,
        sharedGenreSamples,
        mutualSamples,
    ] = await Promise.all([
        sharedAppleTracks > 0
            ? fetchAppleTrackSamples(intersectIds(appleA, appleB))
            : Promise.resolve([]),
        sharedNicheTracks > 0
            ? fetchNicheTrackSamples(intersectIds(nicheA, nicheB))
            : Promise.resolve([]),
        sharedNichePlays > 0
            ? fetchNicheTrackSamples(intersectIds(nichePlayA, nichePlayB))
            : Promise.resolve([]),
        sharedFeedEvents > 0
            ? fetchAppleTrackSamples(intersectIds(feedA, feedB))
            : Promise.resolve([]),
        sharedGenres > 0
            ? fetchGenreSamples(intersectIds(genresA, genresB))
            : Promise.resolve([]),
        mutualFriends > 0
            ? fetchMutualSamples(mutualFriendIds(friendsA, friendsB))
            : Promise.resolve([]),
    ])

    const reason: MatchReason = {
        sharedAppleTracks,
        sharedNicheTracks,
        sharedNichePlays,
        sharedFeedEvents,
        sharedGenres,
        mutuals,
        topReasons: [],
    }
    if (sharedAppleTrackSamples.length > 0) reason.sharedAppleTrackSamples = sharedAppleTrackSamples
    if (sharedNicheTrackSamples.length > 0) reason.sharedNicheTrackSamples = sharedNicheTrackSamples
    if (sharedNichePlayTrackSamples.length > 0) reason.sharedNichePlayTrackSamples = sharedNichePlayTrackSamples
    if (sharedFeedTrackSamples.length > 0) reason.sharedFeedTrackSamples = sharedFeedTrackSamples
    if (sharedGenreSamples.length > 0) reason.sharedGenreSamples = sharedGenreSamples
    if (mutualSamples.length > 0) reason.mutualSamples = mutualSamples
    reason.topReasons = buildTopReasons(reason)

    return { score, reason }
}

export async function getCandidatesForUser(userId: string): Promise<string[]> {
    const [appleTracks, nicheTracks, nichePlays, friendIds] = await Promise.all([
        fetchTrackSets(userId),
        fetchNicheTrackSets(userId),
        fetchNichePlayTrackSet(userId),
        fetchFriendIds(userId),
    ])

    const candidateIds = new Set<string>(friendIds)

    const appleTrackList = [...appleTracks].slice(0, 40)
    if (appleTrackList.length > 0) {
        const [likeHits, saveHits] = await Promise.all([
            supabase.schema("public").from("track_likes").select("user_id").in("track_id", appleTrackList).neq("user_id", userId).limit(80),
            supabase.schema("public").from("track_saves").select("user_id").in("track_id", appleTrackList).neq("user_id", userId).limit(80),
        ])
        if (likeHits.error) throw new Error(likeHits.error.message)
        if (saveHits.error) throw new Error(saveHits.error.message)
        for (const row of [...(likeHits.data ?? []), ...(saveHits.data ?? [])]) {
            candidateIds.add(row.user_id)
        }
    }

    const nicheTrackList = [...nicheTracks].slice(0, 40)
    if (nicheTrackList.length > 0) {
        const [likeHits, saveHits] = await Promise.all([
            supabase.schema("public").from("niche_track_likes").select("liker_id").in("track_id", nicheTrackList).neq("liker_id", userId).limit(80),
            supabase.schema("public").from("niche_track_saves").select("saver_id").in("track_id", nicheTrackList).neq("saver_id", userId).limit(80),
        ])
        if (likeHits.error) throw new Error(likeHits.error.message)
        if (saveHits.error) throw new Error(saveHits.error.message)
        for (const row of likeHits.data ?? []) candidateIds.add(row.liker_id)
        for (const row of saveHits.data ?? []) candidateIds.add(row.saver_id)
    }

    const playTrackList = [...nichePlays].slice(0, 40)
    if (playTrackList.length > 0) {
        const { data: playHits, error: playErr } = await supabase
            .schema("public")
            .from("niche_track_play_events")
            .select("user_id")
            .in("track_id", playTrackList)
            .neq("user_id", userId)
            .limit(80)
        if (playErr) throw new Error(playErr.message)
        for (const row of playHits ?? []) candidateIds.add(row.user_id)
    }

    const { data: following, error: followingErr } = await supabase
        .schema("public")
        .from("follows")
        .select("following_id")
        .eq("follower_id", userId)
        .limit(100)
    if (followingErr) throw new Error(followingErr.message)
    for (const row of following ?? []) {
        candidateIds.add(row.following_id)
    }

    candidateIds.delete(userId)
    return [...candidateIds].slice(0, CANDIDATE_LIMIT)
}

export async function expirePendingMatches(): Promise<number> {
    const now = new Date().toISOString()
    const { data, error } = await supabase
        .schema("public")
        .from("music_matches")
        .update({ status: "expired" })
        .eq("status", "pending")
        .lt("expires_at", now)
        .select("id")
    if (error) throw new Error(error.message)
    return (data ?? []).length
}

export async function createMatch(userA: string, userB: string, score: number, reason: MatchReason) {
    const [low, high] = orderedPair(userA, userB)
    const matchId = generateRandomId(16)
    const { data, error } = await supabase
        .schema("public")
        .from("music_matches")
        .insert({
            id: matchId,
            user_a_id: low,
            user_b_id: high,
            score,
            reason_json: reason,
            status: "pending",
        })
        .select("id")
        .single()
    if (error) throw new Error(error.message)
    return data
}

export async function findDirectConversationId(userA: string, userB: string): Promise<string | null> {
    const { data: mine, error } = await supabase
        .from("conversation_members")
        .select("conversation_id")
        .eq("user_id", userA)
    if (error || !mine?.length) return null

    const convIds = [...new Set(mine.map((m) => m.conversation_id))]
    const { data: members, error: mErr } = await supabase
        .from("conversation_members")
        .select("conversation_id, user_id")
        .in("conversation_id", convIds)
    if (mErr || !members) return null

    const byConv = new Map<string, Set<string>>()
    for (const row of members) {
        if (!byConv.has(row.conversation_id)) byConv.set(row.conversation_id, new Set())
        byConv.get(row.conversation_id)!.add(row.user_id)
    }
    for (const [cid, set] of byConv) {
        if (set.size === 2 && set.has(userA) && set.has(userB)) return cid
    }
    return null
}

export async function createOrGetDirectConversation(userA: string, userB: string) {
    const existing = await findDirectConversationId(userA, userB)
    if (existing) {
        const { data, error } = await supabase
            .from("conversations")
            .select("id, created_at, last_message_id, last_message_at, name")
            .eq("id", existing)
            .single()
        if (error) throw new Error(error.message)
        return { conversation: data, created: false }
    }

    const conversationId = generateRandomId(12)
    const { error: cErr } = await supabase.from("conversations").insert({
        id: conversationId,
        name: null,
    })
    if (cErr) throw new Error(cErr.message)

    const { error: memErr } = await supabase.from("conversation_members").insert([
        { conversation_id: conversationId, user_id: userA },
        { conversation_id: conversationId, user_id: userB },
    ])
    if (memErr) {
        await supabase.from("conversations").delete().eq("id", conversationId)
        throw new Error(memErr.message)
    }

    const { data, error } = await supabase
        .from("conversations")
        .select("id, created_at, last_message_id, last_message_at, name")
        .eq("id", conversationId)
        .single()
    if (error) throw new Error(error.message)
    return { conversation: data, created: true }
}

export { MIN_SCORE }
