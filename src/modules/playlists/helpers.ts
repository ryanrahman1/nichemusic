export function encodePlaylistCursor(cursor: { sortKey: number; createdAt: string }) {
    return Buffer.from(JSON.stringify(cursor)).toString("base64url")
}

export function decodePlaylistCursor(cursor?: string) {
    if (!cursor) return null

    try {
        const parsed = JSON.parse(Buffer.from(cursor, "base64url").toString("utf8"))

        if (
            typeof parsed.sortKey !== "number" ||
            typeof parsed.createdAt !== "string"
        ) {
            return null
        }

        return parsed as { sortKey: number; createdAt: string }
    } catch {
        return null
    }
}

export function encodeCursor(cursor: { createdAt: string; id: string }) {
    return Buffer.from(JSON.stringify(cursor)).toString("base64url")
}

export function decodeCursor(cursor?: string) {
    if (!cursor) return null

    try {
        const parsed = JSON.parse(Buffer.from(cursor, "base64url").toString("utf8"))

        if (
            typeof parsed.createdAt !== "string" ||
            typeof parsed.id !== "string"
        ) {
            return null
        }

        return parsed as { createdAt: string; id: string }
    } catch {
        return null
    }
}

export const PLAYLIST_ITEM_SELECT = `
    id,
    playlist_id,
    niche_track_id,
    added_by_id,
    sort_key,
    created_at,

    track:niche_tracks!playlist_items_niche_track_id_fkey (
        id,
        owner_id,
        name,
        artwork_url,
        music_url,
        release_date,
        explicit,
        duration_ms,
        popularity,
        bpm,
        gain,
        has_lyrics,
        moment_url,
        visibility,
        like_count,
        save_count,
        share_count,
        created_at,
        updated_at,

        owner:profiles!niche_tracks_owner_id_fkey (
            id,
            username,
            display_name,
            avatar_url,
            is_verified,
            verification_type
        ),

        metadata:niche_track_metadata (
            mood,
            energy,
            danceability,
            valence,
            intensity,
            topics,
            language,
            explicit_score,
            metadata
        ),

        artists:niche_track_artists (
            is_primary,
            artist:profiles!niche_track_artists_artist_id_fkey (
                id,
                username,
                display_name,
                avatar_url,
                is_verified,
                verification_type
            )
        )
    )
`