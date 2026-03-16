import { supabase } from "../../config/supabase.js"
import { getPostViewerContextMap } from "../posts/helpers.js"

export type FeedMode = "home" | "reels"

export type FeedCursor = {
    offset: number
}

export type FeedServiceParams = {
    userId?: string
    limit: number
    cursor?: string | undefined
}

type FeedPostCandidate = {
    id: string
    owner_id: string | null
    group_id: string | null
    kind: string
    track_id: string | null
    visibility: string
    like_count: number
    repost_count: number
    comment_count: number
    view_count: number
    created_at: string
    updated_at: string | null
    content: Record<string, unknown>
    has_media: boolean
    has_track: boolean
    has_sound: boolean
    score?: number
    owner?: { id: string; username: string; avatar_url: string | null } | null
    group?: { id: string; name: string | null } | null
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
    groupIds: string[]
    likedPostIds: Set<string>
    repostedPostIds: Set<string>
    skippedPostIds: Set<string>
    viewedPostIds: Set<string>
    likedTrackIds: Set<string>
    savedTrackIds: Set<string>
    fannedArtistIds: Set<string>
    preferredVideo: boolean
}

type RankedFeedEntry =
    | {
        type: "post"
        id: string
        score: number
        createdAt: string
        post: FeedPostCandidate
    }
    | {
        type: "feed_item"
        id: string
        score: number
        createdAt: string
        item: FeedItemRow
    }

export const FEED_CONFIG = {
    home: {
        candidateLimit: 120,
        trendingWindowDays: 14,
        followPostLimit: 60,
        groupPostLimit: 50,
        curatedLimit: 20,
    },
    reels: {
        candidateLimit: 120,
        trendingWindowDays: 14,
        followPostLimit: 50,
        groupPostLimit: 40,
        curatedLimit: 10,
    },
    weights: {
        recencyMaxHours: 72,
        recencyWeight: 60,
        followSourceBoost: 35,
        groupSourceBoost: 18,
        trendingSourceBoost: 12,
        videoKindBoost: 24,
        preferredVideoBoost: 18,
        trackAffinityBoost: 28,
        skipPenalty: 40,
        viewedPenalty: 6,
        baseEngagementLike: 1,
        baseEngagementRepost: 2,
        baseEngagementComment: 2,
        baseEngagementView: 0.02,
        curatedPriorityBase: 1_000_000,
        curatedPriorityStep: 25_000,
        curatedFloatingBase: 15,
    },
} as const

function encodeFeedCursor(cursor: FeedCursor) {
    return Buffer.from(JSON.stringify(cursor)).toString("base64url")
}

function decodeFeedCursor(cursor?: string): FeedCursor {
    if (!cursor) return { offset: 0 }

    try {
        const parsed = JSON.parse(Buffer.from(cursor, "base64url").toString("utf8")) as FeedCursor
        return { offset: Math.max(0, parsed.offset ?? 0) }
    } catch {
        return { offset: 0 }
    }
}

function hoursSince(iso: string) {
    return Math.max(0, (Date.now() - new Date(iso).getTime()) / (1000 * 60 * 60))
}

function getRecencyScore(createdAt: string) {
    const maxHours = FEED_CONFIG.weights.recencyMaxHours
    const hours = hoursSince(createdAt)
    if (hours >= maxHours) return 0
    return ((maxHours - hours) / maxHours) * FEED_CONFIG.weights.recencyWeight
}

async function getUserFeedContext(userId?: string): Promise<FeedUserContext> {
    if (!userId) {
        return {
            followIds: [],
            groupIds: [],
            likedPostIds: new Set(),
            repostedPostIds: new Set(),
            skippedPostIds: new Set(),
            viewedPostIds: new Set(),
            likedTrackIds: new Set(),
            savedTrackIds: new Set(),
            fannedArtistIds: new Set(),
            preferredVideo: false,
        }
    }

    const [
        followsRes,
        groupsRes,
        postLikesRes,
        postRepostsRes,
        postSkipsRes,
        postViewsRes,
        trackLikesRes,
        trackSavesRes,
        artistFansRes,
    ] = await Promise.all([
        supabase.schema("public").from("follows").select("following_id").eq("follower_id", userId),
        supabase.schema("public").from("group_members").select("group_id").eq("user_id", userId),
        supabase.schema("public").from("post_likes").select("post_id").eq("liker_id", userId),
        supabase.schema("public").from("post_reposts").select("post_id").eq("reposter_id", userId),
        supabase.schema("public").from("feed_events").select("entity_id").eq("user_id", userId).eq("entity_type", "post").eq("event_type", "skip"),
        supabase.schema("public").from("feed_events").select("entity_id").eq("user_id", userId).eq("entity_type", "post").in("event_type", ["view", "impression"]),
        supabase.schema("public").from("track_likes").select("track_id").eq("user_id", userId),
        supabase.schema("public").from("track_saves").select("track_id").eq("user_id", userId),
        supabase.schema("public").from("artist_fans").select("artist_id").eq("user_id", userId),
    ])

    const likedTrackIds = new Set((trackLikesRes.data ?? []).map((row) => row.track_id))
    const savedTrackIds = new Set((trackSavesRes.data ?? []).map((row) => row.track_id))
    const fannedArtistIds = new Set((artistFansRes.data ?? []).map((row) => row.artist_id))

    const preferredVideo =
        ((postViewsRes.data ?? []).length + (Array.from(likedTrackIds).length > 0 ? 3 : 0)) > 5

    return {
        followIds: (followsRes.data ?? []).map((row) => row.following_id),
        groupIds: (groupsRes.data ?? []).map((row) => row.group_id),
        likedPostIds: new Set((postLikesRes.data ?? []).map((row) => row.post_id)),
        repostedPostIds: new Set((postRepostsRes.data ?? []).map((row) => row.post_id)),
        skippedPostIds: new Set((postSkipsRes.data ?? []).map((row) => row.entity_id)),
        viewedPostIds: new Set((postViewsRes.data ?? []).map((row) => row.entity_id)),
        likedTrackIds,
        savedTrackIds,
        fannedArtistIds,
        preferredVideo,
    }
}

async function fetchJoinedPosts(postIds: string[]) {
    if (!postIds.length) return []

    const { data, error } = await supabase
        .schema("public")
        .from("posts")
        .select("*, owner:profiles!posts_owner_id_fkey(id, username, avatar_url), group:groups!posts_group_id_fkey(id, name)")
        .in("id", postIds)

    if (error) throw new Error(error.message)

    const map = new Map((data ?? []).map((post) => [post.id, post]))
    return postIds.map((id) => map.get(id)).filter(Boolean) as FeedPostCandidate[]
}

async function fetchTrendingCandidates(mode: FeedMode) {
    const { data, error } = await supabase.rpc("get_feed_trending_post_candidates", {
        window_days: mode === "reels" ? FEED_CONFIG.reels.trendingWindowDays : FEED_CONFIG.home.trendingWindowDays,
        page_limit: mode === "reels" ? FEED_CONFIG.reels.candidateLimit : FEED_CONFIG.home.candidateLimit,
        video_only: mode === "reels",
    })

    if (error) throw new Error(error.message)
    return (data ?? []) as FeedPostCandidate[]
}

async function fetchFollowCandidates(userContext: FeedUserContext, mode: FeedMode) {
    if (!userContext.followIds.length) return []

    const limit = mode === "reels" ? FEED_CONFIG.reels.followPostLimit : FEED_CONFIG.home.followPostLimit
    let query = supabase
        .schema("public")
        .from("posts")
        .select("*, owner:profiles!posts_owner_id_fkey(id, username, avatar_url), group:groups!posts_group_id_fkey(id, name)")
        .in("owner_id", userContext.followIds)
        .order("created_at", { ascending: false })
        .limit(limit)

    if (mode === "reels") query = query.eq("kind", "video")
    if (mode === "home") query = query.in("visibility", ["public", "private"])

    const { data, error } = await query
    if (error) throw new Error(error.message)

    return (data ?? []) as FeedPostCandidate[]
}

async function fetchGroupCandidates(userContext: FeedUserContext, mode: FeedMode) {
    if (!userContext.groupIds.length) return []

    const limit = mode === "reels" ? FEED_CONFIG.reels.groupPostLimit : FEED_CONFIG.home.groupPostLimit
    let query = supabase
        .schema("public")
        .from("posts")
        .select("*, owner:profiles!posts_owner_id_fkey(id, username, avatar_url), group:groups!posts_group_id_fkey(id, name)")
        .in("group_id", userContext.groupIds)
        .eq("visibility", "group")
        .order("created_at", { ascending: false })
        .limit(limit)

    if (mode === "reels") query = query.eq("kind", "video")

    const { data, error } = await query
    if (error) throw new Error(error.message)

    return (data ?? []) as FeedPostCandidate[]
}

async function fetchActiveFeedItems(mode: FeedMode) {
    const { data, error } = await supabase
        .schema("public")
        .from("feed_items")
        .select("*")
        .eq("is_active", true)
        .in("feed_type", [mode, "both"])
        .order("priority", { ascending: true })
        .order("created_at", { ascending: false })
        .limit(mode === "reels" ? FEED_CONFIG.reels.curatedLimit : FEED_CONFIG.home.curatedLimit)

    if (error) throw new Error(error.message)

    const now = Date.now()
    return ((data ?? []) as FeedItemRow[]).filter((item) => {
        const startsOk = !item.starts_at || new Date(item.starts_at).getTime() <= now
        const endsOk = !item.ends_at || new Date(item.ends_at).getTime() >= now
        return startsOk && endsOk
    })
}

function scorePost(post: FeedPostCandidate, mode: FeedMode, source: "follow" | "group" | "trending", ctx: FeedUserContext) {
    let score = 0

    score += getRecencyScore(post.created_at)
    score += post.like_count * FEED_CONFIG.weights.baseEngagementLike
    score += post.repost_count * FEED_CONFIG.weights.baseEngagementRepost
    score += post.comment_count * FEED_CONFIG.weights.baseEngagementComment
    score += post.view_count * FEED_CONFIG.weights.baseEngagementView

    if (source === "follow") score += FEED_CONFIG.weights.followSourceBoost
    if (source === "group") score += FEED_CONFIG.weights.groupSourceBoost
    if (source === "trending") score += FEED_CONFIG.weights.trendingSourceBoost

    if (mode === "reels" && post.kind === "video") score += FEED_CONFIG.weights.videoKindBoost
    if (ctx.preferredVideo && post.kind === "video") score += FEED_CONFIG.weights.preferredVideoBoost

    if (post.track_id && (ctx.likedTrackIds.has(post.track_id) || ctx.savedTrackIds.has(post.track_id))) {
        score += FEED_CONFIG.weights.trackAffinityBoost
    }

    if (ctx.skippedPostIds.has(post.id)) score -= FEED_CONFIG.weights.skipPenalty
    if (ctx.viewedPostIds.has(post.id)) score -= FEED_CONFIG.weights.viewedPenalty

    return score
}

function scoreFeedItem(item: FeedItemRow) {
    if (item.priority >= 1 && item.priority <= 10) {
        return FEED_CONFIG.weights.curatedPriorityBase - item.priority * FEED_CONFIG.weights.curatedPriorityStep
    }

    return FEED_CONFIG.weights.curatedFloatingBase + getRecencyScore(item.created_at)
}

function dedupeAndRankPosts(mode: FeedMode, ctx: FeedUserContext, buckets: { source: "follow" | "group" | "trending"; posts: FeedPostCandidate[] }[]) {
    const map = new Map<string, RankedFeedEntry>()

    for (const bucket of buckets) {
        for (const post of bucket.posts) {
            const score = scorePost(post, mode, bucket.source, ctx)
            const existing = map.get(post.id)

            if (!existing || existing.type !== "post" || score > existing.score) {
                map.set(post.id, {
                    type: "post",
                    id: post.id,
                    score,
                    createdAt: post.created_at,
                    post,
                })
            }
        }
    }

    return Array.from(map.values())
}

function buildRankedFeed(mode: FeedMode, posts: RankedFeedEntry[], feedItems: FeedItemRow[]) {
    const rankedItems: RankedFeedEntry[] = [
        ...posts,
        ...feedItems.map((item) => ({
            type: "feed_item" as const,
            id: item.id,
            score: scoreFeedItem(item),
            createdAt: item.created_at,
            item,
        })),
    ]

    rankedItems.sort((a, b) => {
        if (b.score !== a.score) return b.score - a.score
        const createdDiff = new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
        if (createdDiff !== 0) return createdDiff
        return b.id.localeCompare(a.id)
    })

    if (mode === "reels") {
        return rankedItems.filter((entry) => entry.type === "feed_item" || (entry.type === "post" && entry.post.kind === "video"))
    }

    return rankedItems
}

async function populatePostEntriesWithViewer(userId: string | undefined, entries: RankedFeedEntry[]) {
    const postIds = entries.filter((entry): entry is Extract<RankedFeedEntry, { type: "post" }> => entry.type === "post").map((entry) => entry.post.id)
    const viewerMap = await getPostViewerContextMap(userId, postIds)

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
        }
    })
}

async function getFeed(mode: FeedMode, params: FeedServiceParams) {
    const { userId, limit } = params
    const cursor = decodeFeedCursor(params.cursor)
    const ctx = await getUserFeedContext(userId)

    const [trendingCandidates, followCandidates, groupCandidates, feedItems] = await Promise.all([
        fetchTrendingCandidates(mode),
        fetchFollowCandidates(ctx, mode),
        fetchGroupCandidates(ctx, mode),
        fetchActiveFeedItems(mode),
    ])

    const trendingIdsNeedingJoin = trendingCandidates.map((post) => post.id)
    const joinedTrending = await fetchJoinedPosts(trendingIdsNeedingJoin)

    const rankedPosts = dedupeAndRankPosts(mode, ctx, [
        { source: "trending", posts: joinedTrending },
        { source: "follow", posts: followCandidates },
        { source: "group", posts: groupCandidates },
    ])

    const rankedFeed = buildRankedFeed(mode, rankedPosts, feedItems)
    const slice = rankedFeed.slice(cursor.offset, cursor.offset + limit + 1)
    const hasMore = slice.length > limit
    const pageEntries = hasMore ? slice.slice(0, limit) : slice
    const items = await populatePostEntriesWithViewer(userId, pageEntries)

    return {
        items,
        nextCursor: hasMore ? encodeFeedCursor({ offset: cursor.offset + limit }) : null,
        hasMore,
    }
}

export async function getHomeFeed(params: FeedServiceParams) {
    return getFeed("home", params)
}

export async function getReelsFeed(params: FeedServiceParams) {
    return getFeed("reels", params)
}