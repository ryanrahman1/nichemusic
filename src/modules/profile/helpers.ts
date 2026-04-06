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