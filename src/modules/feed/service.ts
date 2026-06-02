import { supabase } from "../../config/supabase.js"
import { getPostViewerContextMap } from "../posts/helpers.js"

export type FeedCursor = {
    seenIds: string[]
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

type FeedPostCandidate = {
    id: string
    owner_id: string | null
    group_id: string | null
    kind: string
    track_id: string | null
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
    random_key?: number | null
    owner?: FeedOwner | null
    group?: FeedGroup | null
    track?: FeedTrack | null
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

const POST_SELECT = `
*,
owner:profiles!posts_owner_id_fkey(
    id,
    username,
    display_name,
    avatar_url,
    is_private,
    is_verified,
    verification_type
),
group:groups!posts_group_id_fkey(
    id,
    name
),
track:tracks!posts_track_id_fkey(
    id,
    source,
    source_id,
    name,
    artwork_url,
    preview_url,
    artist:artists!tracks_artist_id_fkey(
        id,
        name
    )
)
`

export const FEED_CONFIG = {
    candidateLimits: {
        following: 90,
        friends: 70,
        groups: 70,
        trackAffinity: 70,
        artistAffinity: 70,
        trending: 90,
        explore: 90,
        feedItems: 20,
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

function encodeFeedCursor(cursor: FeedCursor) {
    return Buffer.from(JSON.stringify(cursor)).toString("base64url")
}

function decodeFeedCursor(cursor?: string): FeedCursor {
    if (!cursor) return { seenIds: [] }

    try {
        const parsed = JSON.parse(Buffer.from(cursor, "base64url").toString("utf8")) as Partial<FeedCursor>
        return {
            seenIds: Array.isArray(parsed.seenIds)
                ? parsed.seenIds
                    .filter((id): id is string => typeof id === "string")
                    .slice(-FEED_CONFIG.seen.cursorMaxSeenIds)
                : [],
        }
    } catch {
        return { seenIds: [] }
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
    if (!canSeePost(post, ctx, viewerId)) return true

    if (ctx.seenPostIds.has(post.id)) return true
    if (ctx.skippedPostIds.has(post.id)) return true
    if (ctx.viewedPostIds.has(post.id)) return true
    if (ctx.impressedPostIds.has(post.id)) return true

    return false
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
        profileOpenRes,
        blockedRes,
        blockingRes,
    ] = await Promise.all([
        supabase.schema("public").from("follows").select("following_id").eq("follower_id", userId),
        supabase.schema("public").from("follows").select("follower_id").eq("following_id", userId),

        supabase.schema("public").from("friends").select("user_b_id").eq("user_a_id", userId),
        supabase.schema("public").from("friends").select("user_a_id").eq("user_b_id", userId),

        supabase.schema("public").from("group_members").select("group_id").eq("user_id", userId),

        supabase.schema("public").from("post_likes").select("post_id").eq("liker_id", userId),
        supabase.schema("public").from("post_reposts").select("post_id").eq("reposter_id", userId),

        supabase
            .schema("public")
            .from("feed_events")
            .select("entity_id, event_type")
            .eq("user_id", userId)
            .eq("entity_type", "post")
            .in("event_type", ["impression", "view", "skip"])
            .gte("created_at", seenSince)
            .limit(500),

        supabase.schema("public").from("track_likes").select("track_id").eq("user_id", userId),
        supabase.schema("public").from("track_saves").select("track_id").eq("user_id", userId),
        supabase.schema("public").from("artist_fans").select("artist_id").eq("user_id", userId),

        supabase
            .schema("public")
            .from("feed_events")
            .select("entity_id")
            .eq("user_id", userId)
            .eq("entity_type", "profile")
            .eq("event_type", "open_profile")
            .gte("created_at", seenSince)
            .limit(300),

        supabase.schema("public").from("blocks").select("blocked_id").eq("blocker_id", userId),
        supabase.schema("public").from("blocks").select("blocker_id").eq("blocked_id", userId),
    ])

    const feedEvents = feedEventsRes.data ?? []

    const impressedPostIds = new Set(
        feedEvents
            .filter((row) => row.event_type === "impression")
            .map((row) => row.entity_id)
    )

    const viewedPostIds = new Set(
        feedEvents
            .filter((row) => row.event_type === "view")
            .map((row) => row.entity_id)
    )

    const skippedPostIds = new Set(
        feedEvents
            .filter((row) => row.event_type === "skip")
            .map((row) => row.entity_id)
    )

    const seenPostIds = new Set(feedEvents.map((row) => row.entity_id))

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
        openedProfileIds: new Set(uniqueStrings((profileOpenRes.data ?? []).map((row) => row.entity_id))),

        blockedUserIds: new Set(uniqueStrings((blockedRes.data ?? []).map((row) => row.blocked_id))),
        blockingUserIds: new Set(uniqueStrings((blockingRes.data ?? []).map((row) => row.blocker_id))),
    }
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

    const { data, error } = await supabase
        .schema("public")
        .from("posts")
        .select(POST_SELECT)
        .in("owner_id", filteredOwnerIds)
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
        .select(POST_SELECT)
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
        .select(POST_SELECT)
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
    if (!ctx.fannedArtistIds.size) return []

    // Supabase nested filtering on joined artist ids can get annoying.
    // Keep this lightweight: fetch public track posts and filter in Node.
    // With your current scale this is perfectly fine.
    const { data, error } = await supabase
        .schema("public")
        .from("posts")
        .select(POST_SELECT)
        .eq("visibility", "public")
        .not("track_id", "is", null)
        .order("created_at", { ascending: false })
        .limit(limit * 4)

    if (error) throw new Error(error.message)

    return ((data ?? []) as FeedPostCandidate[])
        .filter((post) => {
            const artistId = getPostArtistId(post)
            return artistId ? ctx.fannedArtistIds.has(artistId) : false
        })
        .filter((post) => !shouldExcludePost(post, ctx, viewerId))
        .slice(0, limit)
}

async function fetchTrendingFreshPosts(ctx: FeedUserContext, viewerId: string | null | undefined, limit: number) {
    const since = recentIso(14)

    const { data, error } = await supabase
        .schema("public")
        .from("posts")
        .select(POST_SELECT)
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
        .select(POST_SELECT)
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
            .select(POST_SELECT)
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

async function fetchActiveFeedItems() {
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

export async function getHomeFeed(params: FeedServiceParams) {
    const { userId, limit } = params
    const cursor = decodeFeedCursor(params.cursor)

    const ctx = await getUserFeedContext(userId)

    for (const id of cursor.seenIds) {
        ctx.seenPostIds.add(id)
        ctx.impressedPostIds.add(id)
    }

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
        fetchPostsByOwners(ctx.followIds, ctx, userId, FEED_CONFIG.candidateLimits.following),
        fetchPostsByOwners(ctx.friendIds, ctx, userId, FEED_CONFIG.candidateLimits.friends),
        fetchGroupPosts(ctx, userId, FEED_CONFIG.candidateLimits.groups),
        fetchTrackAffinityPosts(ctx, userId, FEED_CONFIG.candidateLimits.trackAffinity),
        fetchArtistAffinityPosts(ctx, userId, FEED_CONFIG.candidateLimits.artistAffinity),
        fetchTrendingFreshPosts(ctx, userId, FEED_CONFIG.candidateLimits.trending),
        fetchFreshExplorePosts(ctx, userId, FEED_CONFIG.candidateLimits.explore),
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

    const diversifiedPosts = diversifyPosts(rankedPosts, limit + 8)
    const fullFeed = injectPriorityFeedItems(diversifiedPosts, feedItems)

    const pageEntries = fullFeed.slice(0, limit)
    const hasMore = fullFeed.length > limit

    const items = await populateViewer(userId, pageEntries)

    const newPostIds = pageEntries
        .filter((entry): entry is RankedPostEntry => entry.type === "post")
        .map((entry) => entry.id)

    const nextSeenIds = uniqueStrings([...cursor.seenIds, ...newPostIds])
        .slice(-FEED_CONFIG.seen.cursorMaxSeenIds)

    return {
        items,
        nextCursor: hasMore ? encodeFeedCursor({ seenIds: nextSeenIds }) : null,
        hasMore,
    }
}