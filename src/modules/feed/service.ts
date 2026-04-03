import { supabase } from "../../config/supabase.js"
import { getPostViewerContextMap } from "../posts/helpers.js"

export type FeedCursor = {
    offset: number
}

export type FeedServiceParams = {
    userId?: string | null
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
    followerIds: string[]
    groupIds: string[]
    likedPostIds: Set<string>
    repostedPostIds: Set<string>
    skippedPostIds: Set<string>
    viewedPostIds: Set<string>
    likedTrackIds: Set<string>
    savedTrackIds: Set<string>
    fannedArtistIds: Set<string>
    openedProfileIds: Set<string>
}

type RankedPostEntry = {
    type: "post"
    id: string
    score: number
    createdAt: string
    source: "following" | "followers" | "trending" | "recommended"
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

export const FEED_CONFIG = {
    candidateLimits: {
        following: 60,
        followers: 40,
        trending: 60,
        recommended: 40,
        feedItems: 20,
    },
    recency: {
        maxHours: 96,
        weight: 50,
    },
    weights: {
        followingBoost: 120,
        followersBoost: 70,
        trendingBoost: 35,
        recommendedBoost: 50,
        likeWeight: 1,
        repostWeight: 2,
        commentWeight: 2,
        viewWeight: 0.02,
        videoBoost: 8,
        trackAffinityBoost: 20,
        artistAffinityBoost: 16,
        skipPenalty: 30,
        viewedPenalty: 5,
        openedProfilePenalty: 4,
        floatingFeedItemBase: 25,
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
    const maxHours = FEED_CONFIG.recency.maxHours
    const hours = hoursSince(createdAt)
    if (hours >= maxHours) return 0
    return ((maxHours - hours) / maxHours) * FEED_CONFIG.recency.weight
}

function getPostTrackArtistId(content: Record<string, unknown>): string | null {
    const track = content["track"]
    if (!track || typeof track !== "object" || Array.isArray(track)) return null

    const artistId = (track as Record<string, unknown>)["artist_id"]
    return typeof artistId === "string" ? artistId : null
}

async function getUserFeedContext(userId?: string | null): Promise<FeedUserContext> {
    if (!userId) {
        return {
            followIds: [],
            followerIds: [],
            groupIds: [],
            likedPostIds: new Set(),
            repostedPostIds: new Set(),
            skippedPostIds: new Set(),
            viewedPostIds: new Set(),
            likedTrackIds: new Set(),
            savedTrackIds: new Set(),
            fannedArtistIds: new Set(),
            openedProfileIds: new Set(),
        }
    }

    const [
        followsRes,
        followersRes,
        groupsRes,
        postLikesRes,
        postRepostsRes,
        skippedRes,
        viewedRes,
        trackLikesRes,
        trackSavesRes,
        artistFansRes,
        profileOpenRes,
    ] = await Promise.all([
        supabase.schema("public").from("follows").select("following_id").eq("follower_id", userId),
        supabase.schema("public").from("follows").select("follower_id").eq("following_id", userId),
        supabase.schema("public").from("group_members").select("group_id").eq("user_id", userId),
        supabase.schema("public").from("post_likes").select("post_id").eq("liker_id", userId),
        supabase.schema("public").from("post_reposts").select("post_id").eq("reposter_id", userId),
        supabase.schema("public").from("feed_events").select("entity_id").eq("user_id", userId).eq("entity_type", "post").eq("event_type", "skip"),
        supabase.schema("public").from("feed_events").select("entity_id").eq("user_id", userId).eq("entity_type", "post").in("event_type", ["view", "impression"]),
        supabase.schema("public").from("track_likes").select("track_id").eq("user_id", userId),
        supabase.schema("public").from("track_saves").select("track_id").eq("user_id", userId),
        supabase.schema("public").from("artist_fans").select("artist_id").eq("user_id", userId),
        supabase.schema("public").from("feed_events").select("entity_id").eq("user_id", userId).eq("entity_type", "profile").eq("event_type", "open_profile"),
    ])

    return {
        followIds: (followsRes.data ?? []).map((row) => row.following_id),
        followerIds: (followersRes.data ?? []).map((row) => row.follower_id),
        groupIds: (groupsRes.data ?? []).map((row) => row.group_id),
        likedPostIds: new Set((postLikesRes.data ?? []).map((row) => row.post_id)),
        repostedPostIds: new Set((postRepostsRes.data ?? []).map((row) => row.post_id)),
        skippedPostIds: new Set((skippedRes.data ?? []).map((row) => row.entity_id)),
        viewedPostIds: new Set((viewedRes.data ?? []).map((row) => row.entity_id)),
        likedTrackIds: new Set((trackLikesRes.data ?? []).map((row) => row.track_id)),
        savedTrackIds: new Set((trackSavesRes.data ?? []).map((row) => row.track_id)),
        fannedArtistIds: new Set((artistFansRes.data ?? []).map((row) => row.artist_id)),
        openedProfileIds: new Set((profileOpenRes.data ?? []).map((row) => row.entity_id)),
    }
}

async function fetchPostsByOwners(ownerIds: string[], limit: number) {
    if (!ownerIds.length) return []

    const { data, error } = await supabase
        .schema("public")
        .from("posts")
        .select("*, owner:profiles!posts_owner_id_fkey(id, username, avatar_url), group:groups!posts_group_id_fkey(id, name), track:tracks!posts_track_id_fkey(id, source, source_id, name, artwork_url, preview_url, artist:artists!tracks_artist_id_fkey(id, name))")
        .in("owner_id", ownerIds)
        .in("visibility", ["public", "private"])
        .order("created_at", { ascending: false })
        .limit(limit)

    if (error) throw new Error(error.message)
    return (data ?? []) as FeedPostCandidate[]
}

async function fetchTrendingPosts(limit: number) {
    const { data, error } = await supabase
        .schema("public")
        .from("posts")
        .select("*, owner:profiles!posts_owner_id_fkey(id, username, avatar_url), group:groups!posts_group_id_fkey(id, name), track:tracks!posts_track_id_fkey(id, source, source_id, name, artwork_url, preview_url, artist:artists!tracks_artist_id_fkey(id, name))")
        .eq("visibility", "public")
        .order("like_count", { ascending: false })
        .order("repost_count", { ascending: false })
        .order("comment_count", { ascending: false })
        .order("created_at", { ascending: false })
        .limit(limit)

    if (error) throw new Error(error.message)
    return (data ?? []) as FeedPostCandidate[]
}

async function fetchRecommendedPosts(ctx: FeedUserContext, limit: number) {
    let query = supabase
        .schema("public")
        .from("posts")
        .select("*, owner:profiles!posts_owner_id_fkey(id, username, avatar_url), group:groups!posts_group_id_fkey(id, name), track:tracks!posts_track_id_fkey(id, source, source_id, name, artwork_url, preview_url, artist:artists!tracks_artist_id_fkey(id, name))")
        .eq("visibility", "public")
        .order("created_at", { ascending: false })
        .limit(limit * 2)

    const { data, error } = await query
    if (error) throw new Error(error.message)

    const posts = (data ?? []) as FeedPostCandidate[]

    return posts.filter((post) => {
        if (ctx.followIds.includes(post.owner_id ?? "")) return false
        if (ctx.followerIds.includes(post.owner_id ?? "")) return false
        if (ctx.skippedPostIds.has(post.id)) return false
        return true
    }).slice(0, limit)
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

function scorePost(post: FeedPostCandidate, source: RankedPostEntry["source"], ctx: FeedUserContext) {
    let score = 0

    score += getRecencyScore(post.created_at)
    score += post.like_count * FEED_CONFIG.weights.likeWeight
    score += post.repost_count * FEED_CONFIG.weights.repostWeight
    score += post.comment_count * FEED_CONFIG.weights.commentWeight
    score += post.view_count * FEED_CONFIG.weights.viewWeight

    if (source === "following") score += FEED_CONFIG.weights.followingBoost
    if (source === "followers") score += FEED_CONFIG.weights.followersBoost
    if (source === "trending") score += FEED_CONFIG.weights.trendingBoost
    if (source === "recommended") score += FEED_CONFIG.weights.recommendedBoost

    if (post.kind === "video") score += FEED_CONFIG.weights.videoBoost

    if (post.track_id && (ctx.likedTrackIds.has(post.track_id) || ctx.savedTrackIds.has(post.track_id))) {
        score += FEED_CONFIG.weights.trackAffinityBoost
    }

    const artistId = getPostTrackArtistId(post.content)
    if (artistId && ctx.fannedArtistIds.has(artistId)) score += FEED_CONFIG.weights.artistAffinityBoost

    if (ctx.skippedPostIds.has(post.id)) score -= FEED_CONFIG.weights.skipPenalty
    if (ctx.viewedPostIds.has(post.id)) score -= FEED_CONFIG.weights.viewedPenalty
    if (post.owner_id && ctx.openedProfileIds.has(post.owner_id)) score -= FEED_CONFIG.weights.openedProfilePenalty

    return score
}

function rankPostBuckets(ctx: FeedUserContext, buckets: { source: RankedPostEntry["source"]; posts: FeedPostCandidate[] }[]) {
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
    const postIds = entries.filter((entry): entry is RankedPostEntry => entry.type === "post").map((entry) => entry.post.id)
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
        }
    })
}

export async function getHomeFeed(params: FeedServiceParams) {
    const { userId, limit } = params
    const cursor = decodeFeedCursor(params.cursor)
    const ctx = await getUserFeedContext(userId)

    const [followingPosts, followerPosts, trendingPosts, recommendedPosts, feedItems] = await Promise.all([
        fetchPostsByOwners(ctx.followIds, FEED_CONFIG.candidateLimits.following),
        fetchPostsByOwners(ctx.followerIds, FEED_CONFIG.candidateLimits.followers),
        fetchTrendingPosts(FEED_CONFIG.candidateLimits.trending),
        fetchRecommendedPosts(ctx, FEED_CONFIG.candidateLimits.recommended),
        fetchActiveFeedItems(),
    ])

    const rankedPosts = rankPostBuckets(ctx, [
        { source: "following", posts: followingPosts },
        { source: "followers", posts: followerPosts },
        { source: "trending", posts: trendingPosts },
        { source: "recommended", posts: recommendedPosts },
    ])

    const fullFeed = injectPriorityFeedItems(rankedPosts, feedItems)
    const slice = fullFeed.slice(cursor.offset, cursor.offset + limit + 1)
    const hasMore = slice.length > limit
    const pageEntries = hasMore ? slice.slice(0, limit) : slice
    const items = await populateViewer(userId, pageEntries)

    return {
        items,
        nextCursor: hasMore ? encodeFeedCursor({ offset: cursor.offset + limit }) : null,
        hasMore,
    }
}