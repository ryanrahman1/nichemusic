import { supabase } from "../../config/supabase.js"
import {
    buildTopReasons,
    computePairScore,
    createMatch,
    expirePendingMatches,
    fetchAppleTrackSamples,
    fetchGenreSamples,
    fetchMutualSamples,
    fetchNicheTrackSamples,
    intersectIds,
    MIN_SCORE,
    mutualFriendIds,
    type MatchReason,
    type PairCounts,
    type TasteProfile,
} from "./helpers.js"

const CANDIDATE_LIMIT = 40
const RECENT_MATCH_DAYS = 14
const PAIR_COOLDOWN_DAYS = 90
const DAY_MS = 24 * 60 * 60 * 1000

type GenerationContext = {
    users: string[]
    taste: Map<string, TasteProfile>
    appleTrackUsers: Map<string, Set<string>>
    nicheTrackUsers: Map<string, Set<string>>
    playTrackUsers: Map<string, Set<string>>
    usersWithRecentMatch: Set<string>
    blockedPairs: Set<string>
    matchedThisRun: Set<string>
}

function daysAgoIso(days: number) {
    return new Date(Date.now() - days * DAY_MS).toISOString()
}

function orderedPair(userA: string, userB: string): [string, string] {
    return userA < userB ? [userA, userB] : [userB, userA]
}

function pairKey(userA: string, userB: string) {
    const [low, high] = orderedPair(userA, userB)
    return `${low}|${high}`
}

function emptyTaste(): TasteProfile {
    return {
        apple: new Set(),
        niche: new Set(),
        plays: new Set(),
        feed: new Set(),
        genres: new Set(),
        friends: new Set(),
        following: new Set(),
    }
}

function getTaste(ctx: GenerationContext, userId: string) {
    let taste = ctx.taste.get(userId)
    if (!taste) {
        taste = emptyTaste()
        ctx.taste.set(userId, taste)
    }
    return taste
}

function addTrackUser(index: Map<string, Set<string>>, trackId: string, userId: string) {
    if (!index.has(trackId)) index.set(trackId, new Set())
    index.get(trackId)!.add(userId)
}

function getCandidates(ctx: GenerationContext, userId: string) {
    const taste = ctx.taste.get(userId) ?? emptyTaste()
    const candidateIds = new Set<string>(taste.friends)

    for (const trackId of [...taste.apple].slice(0, 40)) {
        for (const otherId of ctx.appleTrackUsers.get(trackId) ?? []) {
            if (otherId !== userId) candidateIds.add(otherId)
        }
    }
    for (const trackId of [...taste.niche].slice(0, 40)) {
        for (const otherId of ctx.nicheTrackUsers.get(trackId) ?? []) {
            if (otherId !== userId) candidateIds.add(otherId)
        }
    }
    for (const trackId of [...taste.plays].slice(0, 40)) {
        for (const otherId of ctx.playTrackUsers.get(trackId) ?? []) {
            if (otherId !== userId) candidateIds.add(otherId)
        }
    }
    for (const otherId of taste.following) {
        if (otherId !== userId) candidateIds.add(otherId)
    }

    candidateIds.delete(userId)
    return [...candidateIds].slice(0, CANDIDATE_LIMIT)
}

async function buildReason(
    tasteA: TasteProfile,
    tasteB: TasteProfile,
    counts: PairCounts
): Promise<MatchReason> {
    const [
        sharedAppleTrackSamples,
        sharedNicheTrackSamples,
        sharedNichePlayTrackSamples,
        sharedFeedTrackSamples,
        sharedGenreSamples,
        mutualSamples,
    ] = await Promise.all([
        counts.sharedAppleTracks > 0
            ? fetchAppleTrackSamples(intersectIds(tasteA.apple, tasteB.apple))
            : Promise.resolve([]),
        counts.sharedNicheTracks > 0
            ? fetchNicheTrackSamples(intersectIds(tasteA.niche, tasteB.niche))
            : Promise.resolve([]),
        counts.sharedNichePlays > 0
            ? fetchNicheTrackSamples(intersectIds(tasteA.plays, tasteB.plays))
            : Promise.resolve([]),
        counts.sharedFeedEvents > 0
            ? fetchAppleTrackSamples(intersectIds(tasteA.feed, tasteB.feed))
            : Promise.resolve([]),
        counts.sharedGenres > 0
            ? fetchGenreSamples(intersectIds(tasteA.genres, tasteB.genres))
            : Promise.resolve([]),
        counts.mutualFriends > 0
            ? fetchMutualSamples(mutualFriendIds(tasteA.friends, tasteB.friends))
            : Promise.resolve([]),
    ])

    const reason: MatchReason = {
        sharedAppleTracks: counts.sharedAppleTracks,
        sharedNicheTracks: counts.sharedNicheTracks,
        sharedNichePlays: counts.sharedNichePlays,
        sharedFeedEvents: counts.sharedFeedEvents,
        sharedGenres: counts.sharedGenres,
        mutuals: counts.mutuals,
        topReasons: [],
    }
    if (sharedAppleTrackSamples.length > 0) reason.sharedAppleTrackSamples = sharedAppleTrackSamples
    if (sharedNicheTrackSamples.length > 0) reason.sharedNicheTrackSamples = sharedNicheTrackSamples
    if (sharedNichePlayTrackSamples.length > 0) reason.sharedNichePlayTrackSamples = sharedNichePlayTrackSamples
    if (sharedFeedTrackSamples.length > 0) reason.sharedFeedTrackSamples = sharedFeedTrackSamples
    if (sharedGenreSamples.length > 0) reason.sharedGenreSamples = sharedGenreSamples
    if (mutualSamples.length > 0) reason.mutualSamples = mutualSamples
    reason.topReasons = buildTopReasons(reason)
    return reason
}

async function loadGenerationContext(): Promise<GenerationContext> {
    const recentSince = daysAgoIso(RECENT_MATCH_DAYS)
    const pairSince = daysAgoIso(PAIR_COOLDOWN_DAYS)

    const [
        profilesRes,
        appleLikesRes,
        appleSavesRes,
        nicheLikesRes,
        nicheSavesRes,
        nichePlaysRes,
        feedEventsRes,
        friendsRes,
        followsRes,
        trackGenresRes,
        recentMatchesRes,
        pairMatchesRes,
    ] = await Promise.all([
        supabase.schema("public").from("profiles").select("id"),
        supabase.schema("public").from("track_likes").select("user_id, track_id"),
        supabase.schema("public").from("track_saves").select("user_id, track_id"),
        supabase.schema("public").from("niche_track_likes").select("liker_id, track_id"),
        supabase.schema("public").from("niche_track_saves").select("saver_id, track_id"),
        supabase.schema("public").from("niche_track_play_events").select("user_id, track_id"),
        supabase.schema("public").from("feed_events").select("user_id, entity_id").eq("entity_type", "track"),
        supabase.schema("public").from("friends").select("user_a_id, user_b_id"),
        supabase.schema("public").from("follows").select("follower_id, following_id"),
        supabase.schema("public").from("niche_track_genres").select("track_id, genre_id"),
        supabase.schema("public").from("music_matches").select("user_a_id, user_b_id").gte("created_at", recentSince),
        supabase.schema("public").from("music_matches").select("user_a_id, user_b_id").gte("created_at", pairSince),
    ])

    for (const res of [
        profilesRes,
        appleLikesRes,
        appleSavesRes,
        nicheLikesRes,
        nicheSavesRes,
        nichePlaysRes,
        feedEventsRes,
        friendsRes,
        followsRes,
        trackGenresRes,
        recentMatchesRes,
        pairMatchesRes,
    ]) {
        if (res.error) throw new Error(res.error.message)
    }

    const ctx: GenerationContext = {
        users: (profilesRes.data ?? []).map((row) => row.id),
        taste: new Map(),
        appleTrackUsers: new Map(),
        nicheTrackUsers: new Map(),
        playTrackUsers: new Map(),
        usersWithRecentMatch: new Set(),
        blockedPairs: new Set(),
        matchedThisRun: new Set(),
    }

    const trackGenres = new Map<string, Set<string>>()
    for (const row of trackGenresRes.data ?? []) {
        if (!trackGenres.has(row.track_id)) trackGenres.set(row.track_id, new Set())
        trackGenres.get(row.track_id)!.add(row.genre_id)
    }

    const addGenresFromTracks = (userId: string, trackIds: Iterable<string>) => {
        const taste = getTaste(ctx, userId)
        for (const trackId of trackIds) {
            for (const genreId of trackGenres.get(trackId) ?? []) {
                taste.genres.add(genreId)
            }
        }
    }

    for (const row of appleLikesRes.data ?? []) {
        const taste = getTaste(ctx, row.user_id)
        taste.apple.add(row.track_id)
        addTrackUser(ctx.appleTrackUsers, row.track_id, row.user_id)
    }
    for (const row of appleSavesRes.data ?? []) {
        const taste = getTaste(ctx, row.user_id)
        taste.apple.add(row.track_id)
        addTrackUser(ctx.appleTrackUsers, row.track_id, row.user_id)
    }
    for (const row of nicheLikesRes.data ?? []) {
        const taste = getTaste(ctx, row.liker_id)
        taste.niche.add(row.track_id)
        addTrackUser(ctx.nicheTrackUsers, row.track_id, row.liker_id)
    }
    for (const row of nicheSavesRes.data ?? []) {
        const taste = getTaste(ctx, row.saver_id)
        taste.niche.add(row.track_id)
        addTrackUser(ctx.nicheTrackUsers, row.track_id, row.saver_id)
    }
    for (const row of nichePlaysRes.data ?? []) {
        const taste = getTaste(ctx, row.user_id)
        taste.plays.add(row.track_id)
        addTrackUser(ctx.playTrackUsers, row.track_id, row.user_id)
    }
    for (const row of feedEventsRes.data ?? []) {
        const taste = getTaste(ctx, row.user_id)
        taste.feed.add(row.entity_id)
    }

    for (const [userId, taste] of ctx.taste) {
        addGenresFromTracks(userId, [...taste.plays, ...taste.niche])
    }

    for (const row of friendsRes.data ?? []) {
        getTaste(ctx, row.user_a_id).friends.add(row.user_b_id)
        getTaste(ctx, row.user_b_id).friends.add(row.user_a_id)
    }
    for (const row of followsRes.data ?? []) {
        getTaste(ctx, row.follower_id).following.add(row.following_id)
    }

    for (const row of recentMatchesRes.data ?? []) {
        ctx.usersWithRecentMatch.add(row.user_a_id)
        ctx.usersWithRecentMatch.add(row.user_b_id)
    }
    for (const row of pairMatchesRes.data ?? []) {
        ctx.blockedPairs.add(pairKey(row.user_a_id, row.user_b_id))
    }

    return ctx
}

export async function generateMatches() {
    const expired = await expirePendingMatches()
    const ctx = await loadGenerationContext()

    let created = 0
    let skipped = 0

    for (const userId of ctx.users) {
        if (ctx.usersWithRecentMatch.has(userId) || ctx.matchedThisRun.has(userId)) {
            skipped++
            continue
        }

        const tasteA = ctx.taste.get(userId)
        if (!tasteA) {
            skipped++
            continue
        }

        const candidates = getCandidates(ctx, userId)
        let bestCandidate: string | null = null
        let bestCounts: PairCounts | null = null

        for (const candidateId of candidates) {
            if (ctx.matchedThisRun.has(candidateId)) continue
            if (ctx.blockedPairs.has(pairKey(userId, candidateId))) continue

            const tasteB = ctx.taste.get(candidateId)
            if (!tasteB) continue

            const counts = computePairScore(tasteA, tasteB, userId, candidateId)
            if (!bestCounts || counts.score > bestCounts.score) {
                bestCounts = counts
                bestCandidate = candidateId
            }
        }

        if (!bestCandidate || !bestCounts || bestCounts.score <= MIN_SCORE) {
            skipped++
            continue
        }

        if (ctx.usersWithRecentMatch.has(bestCandidate)) {
            skipped++
            continue
        }

        const tasteB = ctx.taste.get(bestCandidate)
        if (!tasteB) {
            skipped++
            continue
        }

        const reason = await buildReason(tasteA, tasteB, bestCounts)
        await createMatch(userId, bestCandidate, bestCounts.score, reason)

        ctx.matchedThisRun.add(userId)
        ctx.matchedThisRun.add(bestCandidate)
        ctx.usersWithRecentMatch.add(userId)
        ctx.usersWithRecentMatch.add(bestCandidate)
        created++
    }

    return { created, skipped, expired }
}
