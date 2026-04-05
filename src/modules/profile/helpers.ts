//helpers

import { supabase } from "../../config/supabase.js"

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