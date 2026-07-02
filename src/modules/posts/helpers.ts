import env from "../../config/env.js"
import { supabase } from "../../config/supabase.js"
import type { CreatePostSchema, CreatePostContentInputSchema, UpdatePostSchema, createCommentSchema, CreateCommentSchema } from "./schemas.js"


type TrackSnapshot = {
    id: string
    source: "spotify" | "apple_music" | "internal" | "deezer"
    source_id: string | null
    name: string | null
    artwork_url: string | null
    preview_url: string | null
    artist_id: string | null
    artist_name: string | null
    album_id: string | null
    release_date: string | null
}

type NicheTrackSnapshot = {
    id: string
    name: string | null
    artwork_url: string | null
    music_url: string | null
    moment_url: string | null
    duration_ms: number | null
    explicit: boolean
    release_date: string | null
    owner_id: string | null
    owner_username: string | null
}

type ExistingPostRow = {
    id: string
    owner_id: string | null
    group_id: string | null
    kind: "text" | "image" | "video" | "track" | "pmo" | "poll"
    track_id: string | null
    niche_track_id: string | null
    visibility: "public" | "private" | "group"
    content: any
    has_media: boolean
    has_track: boolean
    has_sound: boolean
}

export const POST_TRACK_JOIN = `
track:tracks!posts_track_id_fkey(
    id,
    source,
    source_id,
    name,
    artwork_url,
    preview_url,
    artist:artists!tracks_artist_id_fkey(id, name)
)`

export const POST_NICHE_TRACK_JOIN = `
niche_track:niche_tracks!posts_niche_track_id_fkey(
    id,
    name,
    artwork_url,
    music_url,
    moment_url,
    duration_ms,
    explicit,
    release_date,
    owner:profiles!niche_tracks_owner_id_fkey(id, username, avatar_url)
)`

export const POST_LIST_SELECT = `
*,
owner:profiles!posts_owner_id_fkey(id, username, avatar_url),
group:groups!posts_group_id_fkey(id, name),
${POST_TRACK_JOIN},
${POST_NICHE_TRACK_JOIN}
`

function buildPostMediaUrl(objectKey: string): string {
    return `${env.r2.publicBaseUrl}/media/posts/${objectKey}`
}

function assertObjectKeyBelongsToPost(postId: string, objectKey: string) {
    if (!objectKey.startsWith(`${postId}/`)) {
        throw new Error("Invalid media object key")
    }
}

async function fetchTrackSnapshot(trackId: string): Promise<TrackSnapshot> {
    const { data: track, error: trackError } = await supabase
        .schema("public")
        .from("tracks")
        .select("id, source, source_id, name, artwork_url, preview_url, artist_id, album_id, release_date")
        .eq("id", trackId)
        .single()

    if (trackError || !track) {
        throw new Error("Track not found")
    }

    let artistName: string | null = null

    if (track.artist_id) {
        const { data: artist } = await supabase
            .schema("public")
            .from("artists")
            .select("name")
            .eq("id", track.artist_id)
            .maybeSingle()

        artistName = artist?.name ?? null
    }

    return {
        id: track.id,
        source: track.source,
        source_id:
            typeof (track as { source_id?: string | null }).source_id === "string"
                ? (track as { source_id: string }).source_id
                : null,
        name: track.name ?? null,
        artwork_url: track.artwork_url ?? null,
        preview_url: track.preview_url ?? null,
        artist_id: track.artist_id ?? null,
        artist_name: artistName,
        album_id: track.album_id ?? null,
        release_date: track.release_date ?? null,
    }
}

async function fetchNicheTrackSnapshot(nicheTrackId: string): Promise<NicheTrackSnapshot> {
    const { data: track, error: trackError } = await supabase
        .schema("public")
        .from("niche_tracks")
        .select("id, name, artwork_url, music_url, moment_url, duration_ms, explicit, release_date, owner_id, deleted_at, owner:profiles!niche_tracks_owner_id_fkey(username)")
        .eq("id", nicheTrackId)
        .maybeSingle()

    if (trackError || !track || track.deleted_at) {
        throw new Error("Niche track not found")
    }

    const owner = track.owner as { username?: string | null } | null

    return {
        id: track.id,
        name: track.name ?? null,
        artwork_url: track.artwork_url ?? null,
        music_url: track.music_url ?? null,
        moment_url: track.moment_url ?? null,
        duration_ms: track.duration_ms ?? null,
        explicit: track.explicit ?? false,
        release_date: track.release_date ?? null,
        owner_id: track.owner_id ?? null,
        owner_username: owner?.username ?? null,
    }
}

function buildCatalogTrackContent(trackSnapshot: TrackSnapshot) {
    return {
        id: trackSnapshot.id,
        source: trackSnapshot.source,
        source_id: trackSnapshot.source_id,
        title: trackSnapshot.name,
        artist_id: trackSnapshot.artist_id,
        artist_name: trackSnapshot.artist_name,
        album_id: trackSnapshot.album_id,
        artwork_url: trackSnapshot.artwork_url,
        preview_url: trackSnapshot.preview_url,
        release_date: trackSnapshot.release_date,
    }
}

function buildNicheTrackContent(trackSnapshot: NicheTrackSnapshot) {
    return {
        id: trackSnapshot.id,
        title: trackSnapshot.name,
        artwork_url: trackSnapshot.artwork_url,
        music_url: trackSnapshot.music_url,
        moment_url: trackSnapshot.moment_url,
        duration_ms: trackSnapshot.duration_ms,
        explicit: trackSnapshot.explicit,
        release_date: trackSnapshot.release_date,
        owner_id: trackSnapshot.owner_id,
        owner_username: trackSnapshot.owner_username,
    }
}

const NICHE_TRACK_KINDS = new Set(["image", "video", "pmo", "track"])
const CATALOG_TRACK_KINDS = new Set(["pmo"])

function validatePostTrackAttachment(params: {
    kind: CreatePostSchema["kind"]
    trackId: string | null
    nicheTrackId: string | null
}) {
    const { kind, trackId, nicheTrackId } = params

    if (trackId && nicheTrackId) {
        throw new Error("Cannot attach both a catalog track and a niche track")
    }

    if (trackId && !CATALOG_TRACK_KINDS.has(kind)) {
        throw new Error("Catalog tracks can only be attached to PMO posts")
    }

    if (nicheTrackId && !NICHE_TRACK_KINDS.has(kind)) {
        throw new Error("Niche tracks cannot be attached to this post kind")
    }

    if (kind === "text" || kind === "poll") {
        if (trackId || nicheTrackId) {
            throw new Error(`${kind} posts cannot include a track`)
        }
    }

    if (kind === "track" && !nicheTrackId) {
        throw new Error("Track posts must include a niche track")
    }

    if (kind === "pmo" && !trackId && !nicheTrackId) {
        throw new Error("PMO posts must include a track")
    }
}

// validation
function validatePostContentByKind(params: {
    kind: CreatePostSchema["kind"]
    content: CreatePostContentInputSchema
    trackId: string | null
    nicheTrackId: string | null
}) {
    const { kind, content, trackId, nicheTrackId } = params

    validatePostTrackAttachment({ kind, trackId, nicheTrackId })

    if (content.kind !== kind) {
        throw new Error("content.kind must match top-level kind")
    }

    switch (kind) {
        case "text": {
            if (content.media.length > 0) {
                throw new Error("Text posts cannot include media")
            }
            if (content.template) {
                throw new Error("Text posts cannot include a template")
            }
            break
        }

        case "image": {
            if (content.media.length < 1) {
                throw new Error("Image posts must include at least one image")
            }
            if (content.media.some((m) => m.kind !== "image")) {
                throw new Error("Image posts can only contain image media")
            }
            break
        }

        case "video": {
            if (content.media.length < 1) {
                throw new Error("Video posts must include at least one video")
            }
            if (content.media.some((m) => m.kind !== "video")) {
                throw new Error("Video posts can only contain video media")
            }
            break
        }

        case "track": {
            if (content.media.length > 0) {
                throw new Error("Track posts cannot include media")
            }
            break
        }

        case "pmo": {
            if (!content.template || content.template.name !== "pmo") {
                throw new Error("PMO posts must include a PMO template")
            }
            break
        }

        case "poll": {
            if (!content.template || content.template.name !== "poll") {
                throw new Error("Poll posts must include a poll template")
            }
            break
        }

        default:
            throw new Error("Unsupported post kind")
    }
}

export async function cleanPostForInsert(params: {
    ownerId: string
    postId: string
    groupId?: string | null
    kind: CreatePostSchema["kind"]
    visibility: CreatePostSchema["visibility"]
    trackId?: string | null
    nicheTrackId?: string | null
    content: CreatePostContentInputSchema
}) {
    const trackId = params.trackId ?? null
    const nicheTrackId = params.nicheTrackId ?? null

    validatePostContentByKind({
        kind: params.kind,
        content: params.content,
        trackId,
        nicheTrackId,
    })

    const cleanedMedia = params.content.media.map((item) => {
        assertObjectKeyBelongsToPost(params.postId, item.objectKey)

        return {
            kind: item.kind,
            object_key: item.objectKey,
            url: buildPostMediaUrl(item.objectKey),
            width: item.width,
            height: item.height,
            duration_ms: item.kind === "video" ? item.duration_ms ?? null : null,
        }
    })

    const [trackSnapshot, nicheTrackSnapshot] = await Promise.all([
        trackId ? fetchTrackSnapshot(trackId) : Promise.resolve(null),
        nicheTrackId ? fetchNicheTrackSnapshot(nicheTrackId) : Promise.resolve(null),
    ])

    const hasMedia = cleanedMedia.length > 0
    const hasTrack = !!trackSnapshot || !!nicheTrackSnapshot

    // v1: original sound exists only when there is video media.
    // We are not separately storing extracted audio yet.
    const originalSound =
        params.kind === "video" && hasMedia
            ? {
                kind: "original_sound",
                source: "video_media",
            }
            : null

    const hasSound = !!originalSound

    const cleanedContent = {
        version: 1,
        kind: params.kind,
        caption: params.content.caption.trim(),
        media: cleanedMedia,
        track: trackSnapshot ? buildCatalogTrackContent(trackSnapshot) : null,
        niche_track: nicheTrackSnapshot ? buildNicheTrackContent(nicheTrackSnapshot) : null,
        original_sound: originalSound,
        template: params.content.template ?? null,
        metadata: params.content.metadata ?? {},
        analytics: {
            has_media: hasMedia,
            has_track: hasTrack,
            has_original_sound: hasSound,
            media_count: cleanedMedia.length,
        },
    }

    return {
        row: {
            id: params.postId,
            owner_id: params.ownerId,
            group_id: params.groupId ?? null,
            kind: params.kind,
            track_id: trackId,
            niche_track_id: nicheTrackId,
            visibility: params.visibility,
            content: cleanedContent,
            has_media: hasMedia,
            has_track: hasTrack,
            has_sound: hasSound,
        },
        cleanedContent,
    }
}

function validateUpdatedPostContentByKind(params: {
    kind: ExistingPostRow["kind"]
    content: any
    trackId: string | null
    nicheTrackId: string | null
}) {
    const { kind, content, trackId, nicheTrackId } = params

    validatePostTrackAttachment({ kind, trackId, nicheTrackId })

    if (content.kind !== kind) {
        throw new Error("Post kind cannot be changed")
    }

    switch (kind) {
        case "text": {
            if (content.media?.length > 0) {
                throw new Error("Text posts cannot include media")
            }
            break
        }

        case "image": {
            if (!content.media?.length || content.media.some((m: any) => m.kind !== "image")) {
                throw new Error("Image posts must contain image media")
            }
            break
        }

        case "video": {
            if (!content.media?.length || content.media.some((m: any) => m.kind !== "video")) {
                throw new Error("Video posts must contain video media")
            }
            break
        }

        case "track": {
            if (content.media?.length > 0) {
                throw new Error("Track posts cannot include media")
            }
            break
        }

        case "pmo": {
            if (!content.template || content.template.name !== "pmo") {
                throw new Error("PMO posts must include a PMO template")
            }
            break
        }

        case "poll": {
            if (!content.template || content.template.name !== "poll") {
                throw new Error("Poll posts must include a poll template")
            }
            break
        }

        default:
            throw new Error("Unsupported post kind")
    }
}

export async function cleanPostForUpdate(params: {
    existingPost: ExistingPostRow
    updates: UpdatePostSchema
}) {
    const { existingPost, updates } = params

    const nextVisibility = updates.visibility ?? existingPost.visibility

    let nextTrackId = existingPost.track_id
    let nextNicheTrackId = existingPost.niche_track_id

    if (updates.trackId !== undefined) {
        nextTrackId = updates.trackId
        if (updates.trackId) nextNicheTrackId = null
    }

    if (updates.nicheTrackId !== undefined) {
        nextNicheTrackId = updates.nicheTrackId
        if (updates.nicheTrackId) nextTrackId = null
    }

    if (nextTrackId && nextNicheTrackId) {
        throw new Error("Cannot attach both a catalog track and a niche track")
    }

    const baseContent = existingPost.content ?? {}

    const nextContent: any = {
        ...baseContent,
        version: 1,
        kind: existingPost.kind,
        caption:
            updates.content?.caption !== undefined
                ? updates.content.caption.trim()
                : (baseContent.caption ?? ""),
        media: baseContent.media ?? [],
        original_sound: baseContent.original_sound ?? null,
        template:
            updates.content?.template !== undefined
                ? updates.content.template
                : (baseContent.template ?? null),
        metadata:
            updates.content?.metadata !== undefined
                ? updates.content.metadata
                : (baseContent.metadata ?? {}),
    }

    const [trackSnapshot, nicheTrackSnapshot] = await Promise.all([
        nextTrackId ? fetchTrackSnapshot(nextTrackId) : Promise.resolve(null),
        nextNicheTrackId ? fetchNicheTrackSnapshot(nextNicheTrackId) : Promise.resolve(null),
    ])

    nextContent.track = trackSnapshot ? buildCatalogTrackContent(trackSnapshot) : null
    nextContent.niche_track = nicheTrackSnapshot ? buildNicheTrackContent(nicheTrackSnapshot) : null

    const hasMedia = Array.isArray(nextContent.media) && nextContent.media.length > 0
    const hasTrack = !!trackSnapshot || !!nicheTrackSnapshot
    const hasSound = !!nextContent.original_sound

    nextContent.analytics = {
        ...(baseContent.analytics ?? {}),
        has_media: hasMedia,
        has_track: hasTrack,
        has_original_sound: hasSound,
        media_count: hasMedia ? nextContent.media.length : 0,
    }

    validateUpdatedPostContentByKind({
        kind: existingPost.kind,
        content: nextContent,
        trackId: nextTrackId,
        nicheTrackId: nextNicheTrackId,
    })

    return {
        row: {
            visibility: nextVisibility,
            track_id: nextTrackId,
            niche_track_id: nextNicheTrackId,
            content: nextContent,
            has_track: hasTrack,
            updated_at: new Date().toISOString(),
        },
        cleanedContent: nextContent,
    }
}

// comments

export function encodeCommentCursor(input: { createdAt: string; id: string }) {
    return Buffer.from(JSON.stringify(input)).toString("base64url")
}

export function decodeCommentCursor(cursor?: string | null): { createdAt: string; id: string } | null {
    if (!cursor) return null
    const parsed = JSON.parse(Buffer.from(cursor, "base64url").toString("utf8"))
    return { createdAt: parsed.createdAt, id: parsed.id }
}

export async function buildCommentContent(input: CreateCommentSchema) {
    if (input.kind === "text") return { version: 1, kind: "text", text: input.text }

    if (input.kind === "gif") return { version: 1, kind: "gif", text: input.text ?? "", gif: input.gif }

    const { data: track, error: trackError } = await supabase.schema("public").from("tracks").select("id, source, source_id, name, artwork_url, preview_url, artist_id, album_id, release_date").eq("id", input.trackId).single()
    if (trackError || !track) throw new Error("Track not found")

    const { data: artist } = track.artist_id ? await supabase.schema("public").from("artists").select("name").eq("id", track.artist_id).maybeSingle() : { data: null }

    return {
        version: 1,
        kind: "track",
        text: input.text ?? "",
        track: {
            id: track.id,
            source: track.source,
            source_id: (track as any).source_id ?? null,
            title: track.name,
            artist_id: track.artist_id,
            artist_name: artist?.name ?? null,
            album_id: track.album_id,
            artwork_url: track.artwork_url,
            preview_url: track.preview_url,
            release_date: track.release_date,
        },
    }
}

export function addViewerToComments(comments: any[], userId?: string | null) {
    return comments.map((comment) => {
        const isLiked = Array.isArray(comment.comment_likes) && comment.comment_likes.length > 0
        const { comment_likes, ...rest } = comment

        return {
            ...rest,
            viewer: {
                is_owner: !!userId && comment.owner_id === userId,
                is_liked: isLiked,
            },
        }
    })
}


export async function getPostViewerContextMap(userId: string | undefined, postIds: string[]) {
    if (!userId || !postIds.length) return new Map<string, { isLiked: boolean; isReposted: boolean }>()

    const [{ data: likes }, { data: reposts }] = await Promise.all([
        supabase.schema("public").from("post_likes").select("post_id").eq("liker_id", userId).in("post_id", postIds),
        supabase.schema("public").from("post_reposts").select("post_id").eq("reposter_id", userId).in("post_id", postIds),
    ])

    const likedSet = new Set((likes ?? []).map((row) => row.post_id))
    const repostedSet = new Set((reposts ?? []).map((row) => row.post_id))

    return new Map(postIds.map((id) => [id, { isLiked: likedSet.has(id), isReposted: repostedSet.has(id) }]))
}