import { supabase } from "../../config/supabase.js"
import { getOrSetCachedValue } from "../../lib/ttlCache.js"
import { getPostViewerContextMap, POST_LIST_SELECT } from "../posts/helpers.js"

export type FeedCursor = {
    /** Post/feed-item ids already returned to the client for this feed session. */
    deliveredIds: string[]
}

export type FeedServiceParams = {
    userId?: string | null
    limit: number
    cursor?: string | undefined
}

type FeedOwner = {
    id: string
    username: string
    display_name?: string | null
    avatar_url: string | null
    is_private?: boolean | null
    is_verified?: boolean | null
    verification_type?: string | null
}

type FeedGroup = {
    id: string
    name: string | null
}

type FeedArtist = {
    id: string
    name: string
}

type FeedTrack = {
    id: string
    source: string
    source_id: string
    name: string
    artwork_url: string | null
    preview_url: string | null
    artist?: FeedArtist | null
}

type FeedNicheTrack = {
    id: string
    name: string
    artwork_url: string | null
    music_url: string | null
    moment_url: string | null
    duration_ms: number | null
    explicit: boolean
    release_date: string | null
    owner?: { id: string; username: string; avatar_url: string | null } | null
}

type FeedPostCandidate = {
    id: string
    owner_id: string | null
    group_id: string | null
    kind: string
    track_id: string | null
    niche_track_id: string | null
    visibility: "public" | "private" | "group" | string
    like_count: number
    repost_count: number
    comment_count: number
    view_count: number
    share_count?: number | null
    created_at: string
    updated_at: string | null
    content: Record<string, unknown>
    has_media: boolean
    has_track: boolean
    has_sound: boolean
    deleted_at?: string | null
    random_key?: number | null
    owner?: FeedOwner | null
    group?: FeedGroup | null
    track?: FeedTrack | null
    niche_track?: FeedNicheTrack | null
}

type FeedItemRow = {
    id: string
    feed_type: "home" | "reels" | "both"
    kind: string
    title: string | null
    starts_at: string | null
    ends_at: string | null
    priority: number
    is_active: boolean
    content: Record<string, unknown>
    created_at: string
    updated_at: string
}

type FeedUserContext = {
    followIds: string[]
    followerIds: string[]
    friendIds: string[]
    groupIds: string[]

    likedPostIds: Set<string>
    repostedPostIds: Set<string>

    seenPostIds: Set<string>
    skippedPostIds: Set<string>
    viewedPostIds: Set<string>
    impressedPostIds: Set<string>

    likedTrackIds: Set<string>
    savedTrackIds: Set<string>
    fannedArtistIds: Set<string>
    openedProfileIds: Set<string>

    blockedUserIds: Set<string>
    blockingUserIds: Set<string>
}

type FeedSource =
    | "following"
    | "friends"
    | "groups"
    | "track_affinity"
    | "artist_affinity"
    | "trending"
    | "fresh_explore"

type RankedPostEntry = {
    type: "post"
    id: string
    score: number
    createdAt: string
    source: FeedSource
    post: FeedPostCandidate
}

type RankedFeedItemEntry = {
    type: "feed_item"
    id: string
    score: number
    createdAt: string
    item: FeedItemRow
}

type RankedFeedEntry = RankedPostEntry | RankedFeedItemEntry

const FEED_POST_SELECT = POST_LIST_SELECT
const MAX_OWNER_IDS_PER_QUERY = 80
const FEED_CONTEXT_CACHE_TTL_MS = 45_000
const FEED_ITEMS_CACHE_TTL_MS = 120_000

export const FEED_CONFIG = {
    candidateLimits: {
        following: 40,
        friends: 32,
        groups: 32,
        trackAffinity: 32,
        artistAffinity: 32,
        trending: 40,
        explore: 32,
        feedItems: 12,
    },
    recency: {
        maxHours: 168,
        weight: 45,
    },
    seen: {
        recentSeenDays: 7,
        cursorMaxSeenIds: 120,
    },
    sourceBoosts: {
        friends: 130,
        following: 110,
        groups: 85,
        track_affinity: 75,
        artist_affinity: 65,
        trending: 45,
        fresh_explore: 25,
    },
    weights: {
        videoBoost: 8,
        pmoBoost: 14,
        trackAffinityBoost: 22,
        savedTrackBoost: 28,
        artistAffinityBoost: 18,
        openedProfilePenalty: 3,
        floatingFeedItemBase: 25,
    },
    diversity: {
        maxPerOwner: 1,
        maxPerArtist: 2,
        maxPmoPerPage: 4,
        maxVideoPerPage: 4,
    },
} as const

type FeedCandidateLimits = {
    following: number
    friends: number
    groups: number
    trackAffinity: number
    artistAffinity: number
    trending: number
    explore: number
    feedItems: number
}

function getCandidateLimits(pageLimit: number, isPaginating: boolean): FeedCandidateLimits {
    if (!isPaginating) {
        return { ...FEED_CONFIG.candidateLimits }
    }

    const bucket = Math.min(24, Math.max(pageLimit * 3, 16))

    return {
        following: bucket,
        friends: bucket,
        groups: bucket,
        trackAffinity: bucket,
        artistAffinity: bucket,
        trending: bucket,
        explore: 0,
        feedItems: FEED_CONFIG.candidateLimits.feedItems,
    }
}

function fetchBucket(limit: number, loader: () => Promise<FeedPostCandidate[]>) {
    if (limit <= 0) return Promise.resolve([])
    return loader()
}

function encodeFeedCursor(cursor: FeedCursor) {
    return Buffer.from(JSON.stringify(cursor)).toString("base64url")
}

function decodeFeedCursor(cursor?: string): FeedCursor {
    if (!cursor) return { deliveredIds: [] }

    try {
        const parsed = JSON.parse(Buffer.from(cursor, "base64url").toString("utf8")) as Partial<
            FeedCursor & { seenIds?: string[] }
        >
        const rawIds = Array.isArray(parsed.deliveredIds)
            ? parsed.deliveredIds
            : Array.isArray(parsed.seenIds)
              ? parsed.seenIds
              : []

        return {
            deliveredIds: rawIds
                .filter((id): id is string => typeof id === "string")
                .slice(-FEED_CONFIG.seen.cursorMaxSeenIds),
        }
    } catch {
        return { deliveredIds: [] }
    }
}

function hoursSince(iso: string) {
    return Math.max(0, (Date.now() - new Date(iso).getTime()) / (1000 * 60 * 60))
}

function getRecencyScore(createdAt: string) {
    const maxHours = FEED_CONFIG.recency.maxHours
    const hours = hoursSince(createdAt)

    if (hours >= maxHours) return 0

    return ((maxHours - hours) / maxHours) * FEED_CONFIG.recency.weight
}

function getPostArtistId(post: FeedPostCandidate): string | null {
    return post.track?.artist?.id ?? null
}

function uniqueStrings(values: Array<string | null | undefined>) {
    return [...new Set(values.filter((value): value is string => typeof value === "string" && value.length > 0))]
}

function recentIso(daysAgo: number) {
    return new Date(Date.now() - daysAgo * 24 * 60 * 60 * 1000).toISOString()
}

function canSeePost(post: FeedPostCandidate, ctx: FeedUserContext, viewerId?: string | null) {
    if (post.deleted_at) return false
    if (!post.owner_id) return false

    if (ctx.blockedUserIds.has(post.owner_id)) return false
    if (ctx.blockingUserIds.has(post.owner_id)) return false

    if (viewerId && post.owner_id === viewerId) return true

    if (post.visibility === "public") return true

    if (post.visibility === "private") {
        return ctx.followIds.includes(post.owner_id)
    }

    if (post.visibility === "group") {
        return !!post.group_id && ctx.groupIds.includes(post.group_id)
    }

    return false
}

function shouldExcludePost(post: FeedPostCandidate, ctx: FeedUserContext, viewerId?: string | null) {
    return !canSeePost(post, ctx, viewerId)
}

function getSeenPenalty(post: FeedPostCandidate, ctx: FeedUserContext) {
    if (ctx.skippedPostIds.has(post.id)) return 90
    if (ctx.viewedPostIds.has(post.id)) return 70
    if (ctx.impressedPostIds.has(post.id)) return 55
    if (ctx.seenPostIds.has(post.id)) return 45
    return 0
}

function isSeenPost(post: FeedPostCandidate, ctx: FeedUserContext) {
    return (
        ctx.seenPostIds.has(post.id) ||
        ctx.impressedPostIds.has(post.id) ||
        ctx.viewedPostIds.has(post.id) ||
        ctx.skippedPostIds.has(post.id)
    )
}

function engagementScore(post: FeedPostCandidate) {
    return (
        Math.log1p(post.like_count ?? 0) * 8 +
        Math.log1p(post.repost_count ?? 0) * 14 +
        Math.log1p(post.comment_count ?? 0) * 12 +
        Math.log1p(post.view_count ?? 0) * 2 +
        Math.log1p(post.share_count ?? 0) * 10
    )
}

function scorePost(post: FeedPostCandidate, source: FeedSource, ctx: FeedUserContext) {
    let score = 0

    score += FEED_CONFIG.sourceBoosts[source]
    score += getRecencyScore(post.created_at)
    score += engagementScore(post)

    if (post.kind === "video") score += FEED_CONFIG.weights.videoBoost
    if (post.kind === "pmo") score += FEED_CONFIG.weights.pmoBoost

    if (post.track_id && ctx.likedTrackIds.has(post.track_id)) {
        score += FEED_CONFIG.weights.trackAffinityBoost
    }

    if (post.track_id && ctx.savedTrackIds.has(post.track_id)) {
        score += FEED_CONFIG.weights.savedTrackBoost
    }

    const artistId = getPostArtistId(post)
    if (artistId && ctx.fannedArtistIds.has(artistId)) {
        score += FEED_CONFIG.weights.artistAffinityBoost
    }

    if (post.owner_id && ctx.openedProfileIds.has(post.owner_id)) {
        score -= FEED_CONFIG.weights.openedProfilePenalty
    }

    score -= getSeenPenalty(post, ctx)

    // Tiny exploration jitter. Keeps close scores from feeling frozen.
    score += Math.random() * 5

    return score
}

async function getUserFeedContext(userId?: string | null): Promise<FeedUserContext> {
    if (!userId) {
        return {
            followIds: [],
            followerIds: [],
            friendIds: [],
            groupIds: [],
            likedPostIds: new Set(),
            repostedPostIds: new Set(),
            seenPostIds: new Set(),
            skippedPostIds: new Set(),
            viewedPostIds: new Set(),
            impressedPostIds: new Set(),
            likedTrackIds: new Set(),
            savedTrackIds: new Set(),
            fannedArtistIds: new Set(),
            openedProfileIds: new Set(),
            blockedUserIds: new Set(),
            blockingUserIds: new Set(),
        }
    }

    const seenSince = recentIso(FEED_CONFIG.seen.recentSeenDays)

    const [
        followsRes,
        followersRes,
        friendsARes,
        friendsBRes,
        groupsRes,
        postLikesRes,
        postRepostsRes,
        feedEventsRes,
        trackLikesRes,
        trackSavesRes,
        artistFansRes,
        blockedRes,
        blockingRes,
    ] = await Promise.all([
        supabase.schema("public").from("follows").select("following_id").eq("follower_id", userId),
        supabase.schema("public").from("follows").select("follower_id").eq("following_id", userId),

        supabase.schema("public").from("friends").select("user_b_id").eq("user_a_id", userId),
        supabase.schema("public").from("friends").select("user_a_id").eq("user_b_id", userId),

        supabase.schema("public").from("group_members").select("group_id").eq("user_id", userId),

        supabase.schema("public").from("post_likes").select("post_id").eq("liker_id", userId).limit(400),
        supabase.schema("public").from("post_reposts").select("post_id").eq("reposter_id", userId).limit(400),

        supabase
            .schema("public")
            .from("feed_events")
            .select("entity_id, entity_type, event_type")
            .eq("user_id", userId)
            .gte("created_at", seenSince)
            .limit(600),

        supabase.schema("public").from("track_likes").select("track_id").eq("user_id", userId).limit(300),
        supabase.schema("public").from("track_saves").select("track_id").eq("user_id", userId).limit(300),
        supabase.schema("public").from("artist_fans").select("artist_id").eq("user_id", userId).limit(200),

        supabase.schema("public").from("blocks").select("blocked_id").eq("blocker_id", userId),
        supabase.schema("public").from("blocks").select("blocker_id").eq("blocked_id", userId),
    ])

    const feedEvents = feedEventsRes.data ?? []
    const postFeedEvents = feedEvents.filter((row) => row.entity_type === "post")

    const impressedPostIds = new Set(
        postFeedEvents
            .filter((row) => row.event_type === "impression")
            .map((row) => row.entity_id)
    )

    const viewedPostIds = new Set(
        postFeedEvents
            .filter((row) => row.event_type === "view")
            .map((row) => row.entity_id)
    )

    const skippedPostIds = new Set(
        postFeedEvents
            .filter((row) => row.event_type === "skip")
            .map((row) => row.entity_id)
    )

    const seenPostIds = new Set(postFeedEvents.map((row) => row.entity_id))

    return {
        followIds: uniqueStrings((followsRes.data ?? []).map((row) => row.following_id)),
        followerIds: uniqueStrings((followersRes.data ?? []).map((row) => row.follower_id)),
        friendIds: uniqueStrings([
            ...(friendsARes.data ?? []).map((row) => row.user_b_id),
            ...(friendsBRes.data ?? []).map((row) => row.user_a_id),
        ]),
        groupIds: uniqueStrings((groupsRes.data ?? []).map((row) => row.group_id)),

        likedPostIds: new Set(uniqueStrings((postLikesRes.data ?? []).map((row) => row.post_id))),
        repostedPostIds: new Set(uniqueStrings((postRepostsRes.data ?? []).map((row) => row.post_id))),

        seenPostIds,
        skippedPostIds,
        viewedPostIds,
        impressedPostIds,

        likedTrackIds: new Set(uniqueStrings((trackLikesRes.data ?? []).map((row) => row.track_id))),
        savedTrackIds: new Set(uniqueStrings((trackSavesRes.data ?? []).map((row) => row.track_id))),
        fannedArtistIds: new Set(uniqueStrings((artistFansRes.data ?? []).map((row) => row.artist_id))),
        openedProfileIds: new Set(
            uniqueStrings(
                feedEvents
                    .filter(
                        (row) =>
                            row.entity_type === "profile" && row.event_type === "open_profile"
                    )
                    .map((row) => row.entity_id)
            )
        ),

        blockedUserIds: new Set(uniqueStrings((blockedRes.data ?? []).map((row) => row.blocked_id))),
        blockingUserIds: new Set(uniqueStrings((blockingRes.data ?? []).map((row) => row.blocker_id))),
    }
}

async function getUserFeedContextCached(userId?: string | null): Promise<FeedUserContext> {
    if (!userId) return getUserFeedContext(null)

    return getOrSetCachedValue({
        namespace: "feed:user-context",
        key: userId,
        ttlMs: FEED_CONTEXT_CACHE_TTL_MS,
        loader: () => getUserFeedContext(userId),
    })
}

async function fetchPostsByOwners(
    ownerIds: string[],
    ctx: FeedUserContext,
    viewerId: string | null | undefined,
    limit: number
) {
    if (!ownerIds.length) return []

    const filteredOwnerIds = ownerIds.filter((id) => {
        if (ctx.blockedUserIds.has(id)) return false
        if (ctx.blockingUserIds.has(id)) return false
        return true
    })

    if (!filteredOwnerIds.length) return []

    const cappedOwnerIds = filteredOwnerIds.slice(0, MAX_OWNER_IDS_PER_QUERY)

    const { data, error } = await supabase
        .schema("public")
        .from("posts")
        .select(FEED_POST_SELECT)
        .in("owner_id", cappedOwnerIds)
        .order("created_at", { ascending: false })
        .limit(limit * 2)

    if (error) throw new Error(error.message)

    return ((data ?? []) as FeedPostCandidate[])
        .filter((post) => !shouldExcludePost(post, ctx, viewerId))
        .slice(0, limit)
}

async function fetchGroupPosts(ctx: FeedUserContext, viewerId: string | null | undefined, limit: number) {
    if (!ctx.groupIds.length) return []

    const { data, error } = await supabase
        .schema("public")
        .from("posts")
        .select(FEED_POST_SELECT)
        .eq("visibility", "group")
        .in("group_id", ctx.groupIds)
        .order("created_at", { ascending: false })
        .limit(limit * 2)

    if (error) throw new Error(error.message)

    return ((data ?? []) as FeedPostCandidate[])
        .filter((post) => !shouldExcludePost(post, ctx, viewerId))
        .slice(0, limit)
}

async function fetchTrackAffinityPosts(ctx: FeedUserContext, viewerId: string | null | undefined, limit: number) {
    const trackIds = uniqueStrings([...ctx.likedTrackIds, ...ctx.savedTrackIds])

    if (!trackIds.length) return []

    const { data, error } = await supabase
        .schema("public")
        .from("posts")
        .select(FEED_POST_SELECT)
        .eq("visibility", "public")
        .in("track_id", trackIds)
        .order("created_at", { ascending: false })
        .limit(limit * 2)

    if (error) throw new Error(error.message)

    return ((data ?? []) as FeedPostCandidate[])
        .filter((post) => !shouldExcludePost(post, ctx, viewerId))
        .slice(0, limit)
}

async function fetchArtistAffinityPosts(ctx: FeedUserContext, viewerId: string | null | undefined, limit: number) {
    const artistIds = [...ctx.fannedArtistIds].slice(0, 40)
    if (!artistIds.length) return []

    const { data: tracks, error: trackError } = await supabase
        .schema("public")
        .from("tracks")
        .select("id")
        .in("artist_id", artistIds)
        .limit(120)

    if (trackError) throw new Error(trackError.message)

    const trackIds = uniqueStrings((tracks ?? []).map((row) => row.id))
    if (!trackIds.length) return []

    const { data, error } = await supabase
        .schema("public")
        .from("posts")
        .select(FEED_POST_SELECT)
        .eq("visibility", "public")
        .in("track_id", trackIds)
        .order("created_at", { ascending: false })
        .limit(limit * 2)

    if (error) throw new Error(error.message)

    return ((data ?? []) as FeedPostCandidate[])
        .filter((post) => !shouldExcludePost(post, ctx, viewerId))
        .slice(0, limit)
}

async function fetchTrendingFreshPosts(ctx: FeedUserContext, viewerId: string | null | undefined, limit: number) {
    const since = recentIso(14)

    const { data, error } = await supabase
        .schema("public")
        .from("posts")
        .select(FEED_POST_SELECT)
        .eq("visibility", "public")
        .gte("created_at", since)
        .order("like_count", { ascending: false })
        .order("repost_count", { ascending: false })
        .order("comment_count", { ascending: false })
        .order("created_at", { ascending: false })
        .limit(limit * 2)

    if (error) throw new Error(error.message)

    return ((data ?? []) as FeedPostCandidate[])
        .filter((post) => !shouldExcludePost(post, ctx, viewerId))
        .slice(0, limit)
}

async function fetchFreshExplorePosts(ctx: FeedUserContext, viewerId: string | null | undefined, limit: number) {
    const pivot = Math.random()

    const firstQuery = supabase
        .schema("public")
        .from("posts")
        .select(FEED_POST_SELECT)
        .eq("visibility", "public")
        .gte("random_key", pivot)
        .order("random_key", { ascending: true })
        .limit(limit * 2)

    const { data: firstData, error: firstError } = await firstQuery
    if (firstError) throw new Error(firstError.message)

    let posts = (firstData ?? []) as FeedPostCandidate[]

    if (posts.length < limit) {
        const { data: secondData, error: secondError } = await supabase
            .schema("public")
            .from("posts")
            .select(FEED_POST_SELECT)
            .eq("visibility", "public")
            .lt("random_key", pivot)
            .order("random_key", { ascending: true })
            .limit(limit * 2)

        if (secondError) throw new Error(secondError.message)

        posts = [...posts, ...((secondData ?? []) as FeedPostCandidate[])]
    }

    return posts
        .filter((post) => !shouldExcludePost(post, ctx, viewerId))
        .slice(0, limit)
}

async function fetchActiveFeedItemsUncached() {
    const { data, error } = await supabase
        .schema("public")
        .from("feed_items")
        .select("*")
        .eq("is_active", true)
        .in("feed_type", ["home", "both"])
        .order("priority", { ascending: true })
        .order("created_at", { ascending: false })
        .limit(FEED_CONFIG.candidateLimits.feedItems)

    if (error) throw new Error(error.message)

    const now = Date.now()

    return ((data ?? []) as FeedItemRow[]).filter((item) => {
        const startsOk = !item.starts_at || new Date(item.starts_at).getTime() <= now
        const endsOk = !item.ends_at || new Date(item.ends_at).getTime() >= now
        return startsOk && endsOk
    })
}

async function fetchActiveFeedItems() {
    return getOrSetCachedValue({
        namespace: "feed:active-items",
        key: "home",
        ttlMs: FEED_ITEMS_CACHE_TTL_MS,
        loader: fetchActiveFeedItemsUncached,
    })
}

function rankPostBuckets(
    ctx: FeedUserContext,
    buckets: { source: FeedSource; posts: FeedPostCandidate[] }[]
) {
    const map = new Map<string, RankedPostEntry>()

    for (const bucket of buckets) {
        for (const post of bucket.posts) {
            const score = scorePost(post, bucket.source, ctx)
            const existing = map.get(post.id)

            if (!existing || score > existing.score) {
                map.set(post.id, {
                    type: "post",
                    id: post.id,
                    score,
                    createdAt: post.created_at,
                    source: bucket.source,
                    post,
                })
            }
        }
    }

    return Array.from(map.values()).sort((a, b) => {
        if (b.score !== a.score) return b.score - a.score

        const createdDiff = new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
        if (createdDiff !== 0) return createdDiff

        return b.id.localeCompare(a.id)
    })
}

function diversifyPosts(entries: RankedPostEntry[], targetLimit: number) {
    const result: RankedPostEntry[] = []

    const ownerCounts = new Map<string, number>()
    const artistCounts = new Map<string, number>()
    const kindCounts = new Map<string, number>()

    const deferred: RankedPostEntry[] = []

    for (const entry of entries) {
        const post = entry.post
        const ownerId = post.owner_id ?? "unknown"
        const artistId = getPostArtistId(post)
        const kind = post.kind

        const ownerCount = ownerCounts.get(ownerId) ?? 0
        const artistCount = artistId ? artistCounts.get(artistId) ?? 0 : 0
        const kindCount = kindCounts.get(kind) ?? 0

        const exceedsOwner = ownerCount >= FEED_CONFIG.diversity.maxPerOwner
        const exceedsArtist = !!artistId && artistCount >= FEED_CONFIG.diversity.maxPerArtist
        const exceedsPmo = kind === "pmo" && kindCount >= FEED_CONFIG.diversity.maxPmoPerPage
        const exceedsVideo = kind === "video" && kindCount >= FEED_CONFIG.diversity.maxVideoPerPage

        if (exceedsOwner || exceedsArtist || exceedsPmo || exceedsVideo) {
            deferred.push(entry)
            continue
        }

        result.push(entry)
        ownerCounts.set(ownerId, ownerCount + 1)
        if (artistId) artistCounts.set(artistId, artistCount + 1)
        kindCounts.set(kind, kindCount + 1)

        if (result.length >= targetLimit) return result
    }

    // If strict diversity leaves the page too empty, backfill with lower-ranked entries.
    for (const entry of deferred) {
        if (result.some((item) => item.id === entry.id)) continue

        result.push(entry)

        if (result.length >= targetLimit) break
    }

    return result
}

function rankFloatingFeedItems(items: FeedItemRow[]) {
    return items
        .filter((item) => item.priority === -1)
        .map((item) => ({
            type: "feed_item" as const,
            id: item.id,
            score: FEED_CONFIG.weights.floatingFeedItemBase + getRecencyScore(item.created_at),
            createdAt: item.created_at,
            item,
        }))
        .sort((a, b) => {
            if (b.score !== a.score) return b.score - a.score
            return b.id.localeCompare(a.id)
        })
}

function injectPriorityFeedItems(posts: RankedPostEntry[], feedItems: FeedItemRow[]) {
    const priorityItems = feedItems
        .filter((item) => item.priority >= 1 && item.priority <= 10)
        .sort((a, b) => a.priority - b.priority)

    const floatingItems = rankFloatingFeedItems(feedItems)
    const feed: RankedFeedEntry[] = [...posts]

    for (const item of priorityItems) {
        const entry: RankedFeedItemEntry = {
            type: "feed_item",
            id: item.id,
            score: 10_000_000 - item.priority,
            createdAt: item.created_at,
            item,
        }

        const targetIndex = Math.max(0, item.priority - 1)

        if (targetIndex >= feed.length) feed.push(entry)
        else feed.splice(targetIndex, 0, entry)
    }

    for (const entry of floatingItems) {
        const insertIndex = Math.min(feed.length, Math.max(5, Math.floor(feed.length * 0.65)))
        feed.splice(insertIndex, 0, entry)
    }

    return feed
}

async function populateViewer(userId: string | null | undefined, entries: RankedFeedEntry[]) {
    const postIds = entries
        .filter((entry): entry is RankedPostEntry => entry.type === "post")
        .map((entry) => entry.post.id)

    const viewerMap = await getPostViewerContextMap(userId ?? undefined, postIds)

    return entries.map((entry) => {
        if (entry.type === "feed_item") {
            return {
                type: "feed_item" as const,
                item: entry.item,
            }
        }

        return {
            type: "post" as const,
            post: entry.post,
            viewer: viewerMap.get(entry.post.id) ?? { isLiked: false, isReposted: false },
            feedDebug: process.env.NODE_ENV === "production"
                ? undefined
                : {
                    source: entry.source,
                    score: Math.round(entry.score * 100) / 100,
                },
        }
    })
}

function takeFeedPage(entries: RankedFeedEntry[], limit: number): RankedFeedEntry[] {
    if (entries.length <= limit) return entries

    const posts = entries.filter((entry): entry is RankedPostEntry => entry.type === "post")
    const diversifiedPosts = diversifyPosts(posts, limit)
    const selectedPostIds = new Set(diversifiedPosts.map((entry) => entry.id))

    const page: RankedFeedEntry[] = []

    for (const entry of entries) {
        if (page.length >= limit) break

        if (entry.type === "feed_item") {
            page.push(entry)
            continue
        }

        if (selectedPostIds.has(entry.id)) {
            page.push(entry)
        }
    }

    for (const entry of entries) {
        if (page.length >= limit) break
        if (page.some((item) => item.id === entry.id)) continue
        page.push(entry)
    }

    return page.slice(0, limit)
}

export async function getHomeFeed(params: FeedServiceParams) {
    const { userId, limit } = params
    const cursor = decodeFeedCursor(params.cursor)
    const deliveredSet = new Set(cursor.deliveredIds)
    const isPaginating = cursor.deliveredIds.length > 0
    const candidateLimits = getCandidateLimits(limit, isPaginating)

    const ctx = await getUserFeedContextCached(userId)

    const [
        followingPosts,
        friendPosts,
        groupPosts,
        trackAffinityPosts,
        artistAffinityPosts,
        trendingPosts,
        explorePosts,
        feedItems,
    ] = await Promise.all([
        fetchBucket(ctx.followIds.length ? candidateLimits.following : 0, () =>
            fetchPostsByOwners(ctx.followIds, ctx, userId, candidateLimits.following)
        ),
        fetchBucket(ctx.friendIds.length ? candidateLimits.friends : 0, () =>
            fetchPostsByOwners(ctx.friendIds, ctx, userId, candidateLimits.friends)
        ),
        fetchBucket(ctx.groupIds.length ? candidateLimits.groups : 0, () =>
            fetchGroupPosts(ctx, userId, candidateLimits.groups)
        ),
        fetchBucket(
            ctx.likedTrackIds.size || ctx.savedTrackIds.size ? candidateLimits.trackAffinity : 0,
            () => fetchTrackAffinityPosts(ctx, userId, candidateLimits.trackAffinity)
        ),
        fetchBucket(ctx.fannedArtistIds.size ? candidateLimits.artistAffinity : 0, () =>
            fetchArtistAffinityPosts(ctx, userId, candidateLimits.artistAffinity)
        ),
        fetchBucket(candidateLimits.trending, () =>
            fetchTrendingFreshPosts(ctx, userId, candidateLimits.trending)
        ),
        fetchBucket(candidateLimits.explore, () =>
            fetchFreshExplorePosts(ctx, userId, candidateLimits.explore)
        ),
        fetchActiveFeedItems(),
    ])

    const rankedPosts = rankPostBuckets(ctx, [
        { source: "following", posts: followingPosts },
        { source: "friends", posts: friendPosts },
        { source: "groups", posts: groupPosts },
        { source: "track_affinity", posts: trackAffinityPosts },
        { source: "artist_affinity", posts: artistAffinityPosts },
        { source: "trending", posts: trendingPosts },
        { source: "fresh_explore", posts: explorePosts },
    ])

    const unseenPosts = rankedPosts.filter((entry) => !isSeenPost(entry.post, ctx))
    const seenPosts = rankedPosts.filter((entry) => isSeenPost(entry.post, ctx))

    // Unseen first; already-seen posts follow. If everything is seen, keep one ranked feed.
    const orderedPosts =
        unseenPosts.length > 0 ? [...unseenPosts, ...seenPosts] : rankedPosts

    const fullFeed = injectPriorityFeedItems(orderedPosts, feedItems)
    const available = fullFeed.filter((entry) => !deliveredSet.has(entry.id))
    const pageEntries = takeFeedPage(available, limit)
    const hasMore = available.length > pageEntries.length

    const items = await populateViewer(userId, pageEntries)

    const newDeliveredIds = uniqueStrings([
        ...cursor.deliveredIds,
        ...pageEntries.map((entry) => entry.id),
    ]).slice(-FEED_CONFIG.seen.cursorMaxSeenIds)

    return {
        items,
        nextCursor: hasMore ? encodeFeedCursor({ deliveredIds: newDeliveredIds }) : null,
        hasMore,
    }
}