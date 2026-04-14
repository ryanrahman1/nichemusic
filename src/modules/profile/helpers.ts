//helpers

import { supabase } from "../../config/supabase.js"

/** Same shape for `GET /me` and full `GET /users/:username` profile rows. */
export const PROFILE_DETAIL_SELECT =
    "*, user_status(*), profile_song:tracks!profiles_profile_song_id_fkey(id, name, preview_url, artwork_url, source, source_id, artist:artists!tracks_artist_id_fkey(name))"

export type ViewerProfileContext = {
    isSelf: boolean
    /** You follow them; `null` when {@link isSelf} (not applicable). */
    isFollowing: boolean | null
    /** They follow you. */
    isFollowedBy: boolean
    /** You blocked them. */
    isBlocked: boolean
    /** They blocked you. */
    isBlockedBy: boolean
    /** Pending follow request from you to them (e.g. private account). */
    outgoingFollowRequest: boolean
    /** Pending follow request from them to you. */
    incomingFollowRequest: boolean
}

/**
 * Relationship flags between the optional viewer and the profile user.
 * Call with `viewerId === undefined` for unauthenticated requests (all false, no self).
 */
export async function getViewerProfileContext(
    viewerId: string | undefined,
    targetUserId: string
): Promise<ViewerProfileContext> {
    if (!viewerId) {
        return {
            isSelf: false,
            isFollowing: null,
            isFollowedBy: false,
            isBlocked: false,
            isBlockedBy: false,
            outgoingFollowRequest: false,
            incomingFollowRequest: false,
        }
    }

    if (viewerId === targetUserId) {
        return {
            isSelf: true,
            isFollowing: null,
            isFollowedBy: false,
            isBlocked: false,
            isBlockedBy: false,
            outgoingFollowRequest: false,
            incomingFollowRequest: false,
        }
    }

    const [
        followOut,
        followIn,
        blockOut,
        blockIn,
        reqOut,
        reqIn,
    ] = await Promise.all([
        supabase
            .schema("public")
            .from("follows")
            .select("follower_id")
            .eq("follower_id", viewerId)
            .eq("following_id", targetUserId)
            .maybeSingle(),
        supabase
            .schema("public")
            .from("follows")
            .select("follower_id")
            .eq("follower_id", targetUserId)
            .eq("following_id", viewerId)
            .maybeSingle(),
        supabase
            .schema("public")
            .from("blocks")
            .select("blocker_id")
            .eq("blocker_id", viewerId)
            .eq("blocked_id", targetUserId)
            .maybeSingle(),
        supabase
            .schema("public")
            .from("blocks")
            .select("blocker_id")
            .eq("blocker_id", targetUserId)
            .eq("blocked_id", viewerId)
            .maybeSingle(),
        supabase
            .schema("public")
            .from("follow_requests")
            .select("follower_id")
            .eq("follower_id", viewerId)
            .eq("following_id", targetUserId)
            .eq("status", "sent")
            .maybeSingle(),
        supabase
            .schema("public")
            .from("follow_requests")
            .select("follower_id")
            .eq("follower_id", targetUserId)
            .eq("following_id", viewerId)
            .eq("status", "sent")
            .maybeSingle(),
    ])

    const errors = [
        followOut.error,
        followIn.error,
        blockOut.error,
        blockIn.error,
        reqOut.error,
        reqIn.error,
    ].filter(Boolean)
    if (errors.length > 0) {
        throw new Error(errors[0]!.message)
    }

    return {
        isSelf: false,
        isFollowing: !!followOut.data,
        isFollowedBy: !!followIn.data,
        isBlocked: !!blockOut.data,
        isBlockedBy: !!blockIn.data,
        outgoingFollowRequest: !!reqOut.data,
        incomingFollowRequest: !!reqIn.data,
    }
}

export type FollowListProfileRow = {
    id: string
    username: string
    display_name: string | null
    avatar_url: string | null
}

/**
 * Loads public profile fields for the given ids and returns them in the same order as `ids`
 * (skips missing rows, e.g. deleted accounts).
 */
export async function profilesForUserIdsOrdered(ids: string[]): Promise<FollowListProfileRow[]> {
    if (ids.length === 0) return []

    const unique = [...new Set(ids)]
    const { data, error } = await supabase
        .schema("public")
        .from("profiles")
        .select("id, username, display_name, avatar_url")
        .in("id", unique)

    if (error) {
        throw new Error(error.message)
    }

    const map = new Map(
        (data ?? []).map((row) => [
            row.id,
            {
                id: row.id,
                username: row.username,
                display_name: row.display_name,
                avatar_url: row.avatar_url,
            } satisfies FollowListProfileRow,
        ])
    )

    const out: FollowListProfileRow[] = []
    for (const id of ids) {
        const row = map.get(id)
        if (row) out.push(row)
    }
    return out
}

export async function checkFollowing(userId: string, otherUserId: string) {
    const { data, error } = await supabase.schema('public').from('follows').select('*').eq('follower_id', userId).eq('following_id', otherUserId).maybeSingle()
    if (error) { throw new Error(error.message) }
    if (!data) { return false } else { return true }
}

/** Normalized friend row for the Friends tab activity carousel (camelCase JSON). */
export type FriendActivityItem = {
    userId: string
    username: string
    displayName: string | null
    avatarUrl: string | null
    kind: "music" | "text"
    updatedAt: string | null
    track: {
        id: string
        name: string
        artistName: string | null
        artworkUrl: string | null
    } | null
    text: string | null
}

function asRecord(v: unknown): Record<string, unknown> | null {
    if (v == null) return null
    if (Array.isArray(v)) {
        const first = v[0]
        return first != null && typeof first === "object" && !Array.isArray(first)
            ? (first as Record<string, unknown>)
            : null
    }
    if (typeof v === "object") return v as Record<string, unknown>
    return null
}

function pickString(v: unknown): string | null {
    if (typeof v !== "string") return null
    const t = v.trim()
    return t.length > 0 ? t : null
}

function artistNameFromEmbed(artist: unknown): string | null {
    const o = asRecord(artist)
    if (!o) return null
    return pickString(o.name)
}

function profileSongTrackFromRow(ps: unknown): FriendActivityItem["track"] {
    const o = asRecord(ps)
    if (!o) return null
    const id = pickString(o.id)
    const name = pickString(o.name)
    if (!id || !name) return null
    return {
        id,
        name,
        artistName: artistNameFromEmbed(o.artist),
        artworkUrl: pickString(o.artwork_url),
    }
}

function statusTextFromUserStatus(us: Record<string, unknown> | null): string | null {
    if (!us) return null
    for (const key of ["text", "body", "note", "message", "content"] as const) {
        const t = pickString(us[key])
        if (t) return t
    }
    return null
}

function maxIso(a: string | null, b: string | null): string | null {
    if (!a) return b
    if (!b) return a
    return new Date(a).getTime() >= new Date(b).getTime() ? a : b
}

/**
 * Maps `profiles` rows (same shape as {@link PROFILE_DETAIL_SELECT}) into activity cards.
 * Prefers a profile song for the “music” card; otherwise uses a non-empty `user_status` text field.
 */
export function buildFriendActivitiesFromProfileRows(rows: unknown[]): FriendActivityItem[] {
    const out: FriendActivityItem[] = []
    for (const raw of rows) {
        const row = asRecord(raw)
        if (!row) continue
        const userId = pickString(row.id)
        const username = pickString(row.username)
        if (!userId || !username) continue

        const displayName = pickString(row.display_name)
        const avatarUrl = pickString(row.avatar_url)
        const profileUpdated = pickString(row.updated_at)

        const us = asRecord(row.user_status)
        const statusText = statusTextFromUserStatus(us)
        const statusUpdated = maxIso(pickString(us?.updated_at), pickString(us?.created_at))

        const track = profileSongTrackFromRow(row.profile_song)

        let kind: FriendActivityItem["kind"] | null = null
        let text: string | null = null
        let trackOut: FriendActivityItem["track"] = null

        if (track) {
            kind = "music"
            trackOut = track
            text = null
        } else if (statusText) {
            kind = "text"
            text = statusText
            trackOut = null
        }

        if (!kind) continue

        const updatedAt = maxIso(statusUpdated, profileUpdated)

        out.push({
            userId,
            username,
            displayName,
            avatarUrl,
            kind,
            updatedAt,
            track: trackOut,
            text,
        })
    }

    out.sort((a, b) => {
        const ta = a.updatedAt ? new Date(a.updatedAt).getTime() : 0
        const tb = b.updatedAt ? new Date(b.updatedAt).getTime() : 0
        return tb - ta
    })

    return out
}